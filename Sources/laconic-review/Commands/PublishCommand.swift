import ArgumentParser
import Foundation
import LaconicReviewCore

/// Publish open findings from a review report to the MR as discussions.
///
/// Dry-run by default (offline: parse + ledger only); pass `--confirm` to fetch `diff_refs`
/// and actually post. Idempotent — findings already in `<N>.published.json` are skipped.
struct PublishCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "publish",
        abstract: "Publish open findings from a review report to the MR (dry-run unless --confirm)."
    )

    @Argument(help: "Path to the review report markdown (e.g. .claude/reviews/<branch>/1.md).")
    var report: String

    @Flag(help: "Actually post to GitLab. Without it, prints the plan (dry-run, offline).")
    var confirm = false

    @OptionGroup var options: ConnectionOptions

    func run() async throws {
        do {
            try await runInner()
        } catch let e as ValidationError {
            throw e
        } catch {
            throw ValidationError(ErrorExplain.describe(error))
        }
    }

    private func runInner() async throws {
        let reportURL = URL(fileURLWithPath: report)
        let parsed = try ReportParser.parse(try String(contentsOf: reportURL, encoding: .utf8))
        let iid = parsed.header.iid
        let ledgerURL = PublishLedger.url(forReport: reportURL)
        var ledger = try PublishLedger.load(from: ledgerURL)

        let pending = parsed.findings.filter { $0.isOpen && !ledger.published($0.id) }
        let skipped = parsed.findings.count - pending.count

        // Dry run stays offline — no connection, no token, no network.
        guard confirm else {
            print("DRY RUN — \(pending.count) finding(s) would post to MR !\(iid); "
                + "\(skipped) skipped (already published or not open). Re-run with --confirm.\n")
            for finding in pending {
                print("  • [\(finding.scope.rawValue)] \(finding.id) → \(Self.location(finding))")
            }
            return
        }

        // Confirmed: diff_refs is the server's truth for `position`, fetched fresh now —
        // and the MR diffs that tell added lines from context lines (which need both
        // `old_*` and `new_*` coordinates, or GitLab answers `badRequest`). The two
        // reads must describe the same revision: re-check the head SHA after the diff
        // fetch and refetch once if a push landed in between.
        let connection = try options.makeConnection()
        var fetched = try await connection.mergeRequest(iid: iid)
        var lineMaps = DiffParser.lineMaps(for: try await connection.mergeRequestDiffs(iid: iid))
        for _ in 0..<2 {
            let check = try await connection.mergeRequest(iid: iid)
            guard check.diffRefs.headSha != fetched.diffRefs.headSha else { break }
            fetched = check
            lineMaps = DiffParser.lineMaps(for: try await connection.mergeRequestDiffs(iid: iid))
        }
        let (mr, diffRefs) = fetched

        // Pass 1 — post every pending finding, recording its thread URL. Forward cross-links (to a
        // finding posted later in this pass) render as bare ids for now; pass 2 resolves them.
        // A rejected position must not abort the batch: failures are collected and reported at
        // the end, and the ledger keeps only successes so a re-run retries just those.
        var posted = 0
        var demoted = 0
        var failed: [(id: String, reason: String)] = []
        for finding in pending {
            let (body, resolved) = Self.renderedBody(for: finding, ledger: ledger)
            let anchor = finding.position.flatMap { AnchorResolver.resolve($0, in: lineMaps) }
            if finding.position != nil && anchor == nil {
                demoted += 1
                print("  ⚠ \(finding.id): anchor outside the diff — posting as a general note")
            }
            let result: PostedDiscussion
            do {
                result = try await connection.postDiscussion(
                    iid: iid, body: body, position: anchor, diffRefs: diffRefs
                )
            } catch {
                let reason = ErrorExplain.describe(error)
                failed.append((finding.id, reason))
                print("  ✗ \(finding.id) — \(reason)")
                continue
            }
            let url = result.noteID.flatMap { id in mr.webURL.map { "\($0)#note_\(id)" } }
            ledger.record(finding.id, PublishedThread(
                discussionID: result.discussionID, noteID: result.noteID, url: url, resolvedLinks: resolved
            ))
            try ledger.save(to: ledgerURL)   // incremental write — crash-safe across the loop
            posted += 1
            print("  ✓ \(finding.id) → \(url ?? result.discussionID)")
        }

        // Pass 2 — the ledger now holds every URL: rewrite only the notes whose cross-links can
        // resolve to more URLs than they currently show (`resolved_links` is stale). Idempotent —
        // skips already-resolved notes — so a re-run also repairs forward links left bare by an
        // earlier single-pass publish.
        var relinked = 0
        for finding in parsed.findings where !finding.links.isEmpty {
            guard let thread = ledger.thread(for: finding.id), let noteID = thread.noteID else { continue }
            let (body, resolved) = Self.renderedBody(for: finding, ledger: ledger)
            guard Set(resolved) != Set(thread.resolvedLinks) else { continue }
            try await connection.updateNote(
                iid: iid, discussionID: thread.discussionID, noteID: noteID, body: body
            )
            ledger.record(finding.id, PublishedThread(
                discussionID: thread.discussionID, noteID: noteID, url: thread.url, resolvedLinks: resolved
            ))
            try ledger.save(to: ledgerURL)
            relinked += 1
        }

        print("\nPublished \(posted); relinked \(relinked); \(skipped) skipped"
            + (demoted > 0 ? "; \(demoted) anchor(s) demoted to general" : "")
            + (failed.isEmpty ? "" : "; \(failed.count) failed")
            + ". Ledger: \(ledgerURL.lastPathComponent)")
        guard failed.isEmpty else {
            // A transport/decoding failure can throw after GitLab already committed the
            // discussion — the thread exists but the ledger doesn't know it, so a blind
            // re-run could double-post. Say so instead of implying a clean retry.
            throw ValidationError(
                "\(failed.count) finding(s) failed to publish — a failure may still have "
                + "landed server-side; check the MR, then re-run with --confirm to retry "
                + "(posted findings are skipped): "
                + failed.map { "\($0.id) (\($0.reason))" }.joined(separator: "; ")
            )
        }
    }

    /// A human-readable anchor for the dry-run plan.
    private static func location(_ f: Finding) -> String {
        guard f.scope == .line else { return "general" }
        let lines = [f.lineStart, f.lineEnd].compactMap { $0 }.map(String.init).joined(separator: "-")
        return "\(f.file ?? "?"):\(lines) [\(f.lineType.rawValue)]"
    }

    /// Posted body = the finding's verbatim markdown plus a language-neutral footer cross-linking
    /// related findings. Returns the body and the link ids that resolved to a thread URL (the rest
    /// stay bare ids until their thread exists — the publish second pass fills them in).
    private static func renderedBody(for finding: Finding, ledger: PublishLedger) -> (body: String, resolved: [String]) {
        guard !finding.links.isEmpty else { return (finding.markdown, []) }
        var resolved: [String] = []
        let parts = finding.links.map { id -> String in
            guard let url = ledger.url(for: id) else { return id }
            resolved.append(id)
            return "[\(id)](\(url))"
        }
        return (finding.markdown + "\n\n🔗 " + parts.joined(separator: " · "), resolved)
    }
}
