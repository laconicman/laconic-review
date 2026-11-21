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

        // Out-of-hunk inference is only trustworthy when the report was written
        // against this exact head — line numbers are bare coordinates, so a push
        // since the review can slide an anchor onto unrelated code (TD-10). A
        // stamped-but-mismatched head_sha also means in-hunk anchors may be stale.
        let revisionVerified = parsed.header.matchesHead(diffRefs.headSha)
        if let stamped = parsed.header.headSha, stamped != diffRefs.headSha {
            print("  ⚠ report head_sha \(stamped) ≠ MR head \(diffRefs.headSha ?? "?") — "
                + "line anchors may be stale; refresh the review before trusting them")
        }

        // Pass 1 — post every pending finding, recording its thread URL. Forward cross-links (to a
        // finding posted later in this pass) render as bare ids for now; pass 2 resolves them.
        // A rejected position must not abort the batch: failures are collected and reported at
        // the end, and the ledger keeps only successes so a re-run retries just those.
        var posted = 0
        var demoted = 0
        var failed: [(id: String, reason: String)] = []
        for finding in pending {
            let (anchor, revisionGated) = Self.resolvedAnchor(
                for: finding, in: lineMaps, revisionVerified: revisionVerified
            )
            let (body, resolved) = Self.renderedBody(
                for: finding, ledger: ledger,
                includeAnchor: anchor == nil || anchor?.outsideHunks == true
            )
            if finding.position != nil && anchor == nil {
                demoted += 1
                print("  ⚠ \(finding.id): "
                    + (revisionGated
                        ? "out-of-hunk anchor but report revision unverified"
                        : "anchor outside the diff")
                    + " — posting as a general note")
            }
            let outcome: (result: PostedDiscussion, anchorRejected: Bool)
            do {
                outcome = try await Self.postFinding(
                    iid: iid, body: body, anchor: anchor, diffRefs: diffRefs, connection: connection
                )
            } catch {
                let reason = ErrorExplain.describe(error)
                failed.append((finding.id, reason))
                print("  ✗ \(finding.id) — \(reason)")
                continue
            }
            if outcome.anchorRejected {
                demoted += 1
                print("  ⚠ \(finding.id): inferred anchor rejected — posted as a general note")
            }
            let result = outcome.result
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
        // earlier single-pass publish. Same isolation as pass 1: one bad relink must not abort
        // the rest, and the finding itself is already safely posted.
        var relinked = 0
        var relinkFailed: [(id: String, reason: String)] = []
        for finding in parsed.findings where !finding.links.isEmpty {
            guard let thread = ledger.thread(for: finding.id), let noteID = thread.noteID else { continue }
            let (anchor, _) = Self.resolvedAnchor(
                for: finding, in: lineMaps, revisionVerified: revisionVerified
            )
            let (body, resolved) = Self.renderedBody(
                for: finding, ledger: ledger,
                includeAnchor: anchor == nil || anchor?.outsideHunks == true
            )
            guard Set(resolved) != Set(thread.resolvedLinks) else { continue }
            do {
                try await connection.updateNote(
                    iid: iid, discussionID: thread.discussionID, noteID: noteID, body: body
                )
            } catch {
                let reason = ErrorExplain.describe(error)
                relinkFailed.append((finding.id, reason))
                print("  ✗ \(finding.id) relink — \(reason)")
                continue
            }
            ledger.record(finding.id, PublishedThread(
                discussionID: thread.discussionID, noteID: noteID, url: thread.url, resolvedLinks: resolved
            ))
            try ledger.save(to: ledgerURL)
            relinked += 1
        }

        print("\nPublished \(posted); relinked \(relinked); \(skipped) skipped"
            + (demoted > 0 ? "; \(demoted) anchor(s) demoted to general" : "")
            + (failed.isEmpty ? "" : "; \(failed.count) failed")
            + (relinkFailed.isEmpty ? "" : "; \(relinkFailed.count) relink(s) failed")
            + ". Ledger: \(ledgerURL.lastPathComponent)")
        var problems: [String] = []
        if !failed.isEmpty {
            // A transport/decoding failure can throw after GitLab already committed the
            // discussion — the thread exists but the ledger doesn't know it, so a blind
            // re-run could double-post. Say so instead of implying a clean retry.
            problems.append(
                "\(failed.count) finding(s) failed to publish — a failure may still have "
                + "landed server-side; check the MR, then re-run with --confirm to retry "
                + "(posted findings are skipped): "
                + failed.map { "\($0.id) (\($0.reason))" }.joined(separator: "; ")
            )
        }
        if !relinkFailed.isEmpty {
            problems.append(
                "\(relinkFailed.count) relink(s) failed — re-run to retry: "
                + relinkFailed.map { "\($0.id) (\($0.reason))" }.joined(separator: "; ")
            )
        }
        guard problems.isEmpty else { throw ValidationError(problems.joined(separator: " ")) }
    }

    /// Resolve a finding's anchor against the MR diffs. An inferred out-of-hunk
    /// position is returned only when the report's stamped `head_sha` matches the
    /// MR's current head — otherwise the line numbers can't be trusted to mean
    /// the same code, and the caller demotes to a general note (TD-10). The
    /// second tuple element reports that suppression so the caller can say why.
    private static func resolvedAnchor(
        for finding: Finding, in lineMaps: [String: FileLineMap], revisionVerified: Bool
    ) -> (anchor: ResolvedPosition?, revisionGated: Bool) {
        guard let raw = finding.position.flatMap({ AnchorResolver.resolve($0, in: lineMaps) })
        else { return (nil, false) }
        guard raw.outsideHunks, !revisionVerified else { return (raw, false) }
        return (nil, true)
    }

    /// Post one finding. An inferred out-of-hunk anchor can still be rejected —
    /// GitLab unfolds blob lines under size caps — so on a *definite* 400 (the
    /// server answered; nothing was posted) retry once as a general note rather
    /// than lose the finding. Transport errors are never retried: the post may
    /// already have landed, and a retry could double-post.
    private static func postFinding(
        iid: Int, body: String, anchor: ResolvedPosition?,
        diffRefs: DiffRefs, connection: GitLabConnection
    ) async throws -> (result: PostedDiscussion, anchorRejected: Bool) {
        do {
            return (try await connection.postDiscussion(
                iid: iid, body: body, position: anchor, diffRefs: diffRefs
            ), false)
        } catch {
            guard DiscussionPostError.shouldFallbackToGeneralNote(error: error, anchor: anchor)
            else { throw error }
            return (try await connection.postDiscussion(
                iid: iid, body: body, position: nil, diffRefs: diffRefs
            ), true)
        }
    }

    /// A human-readable anchor for the dry-run plan.
    private static func location(_ f: Finding) -> String {
        guard f.scope == .line else { return "general" }
        let lines = [f.lineStart, f.lineEnd].compactMap { $0 }.map(String.init).joined(separator: "-")
        return "\(f.file ?? "?"):\(lines) [\(f.lineType.rawValue)]"
    }

    /// The report's intended location as note text (`file:lines [side]`, or just
    /// `file`) — appended to notes that post without a diff anchor, so a demoted
    /// or fallback general note still tells readers where the finding points.
    private static func anchorLabel(for finding: Finding) -> String? {
        guard let file = finding.file else { return nil }
        guard finding.scope == .line, finding.lineType != .file,
              (finding.lineEnd ?? finding.lineStart) != nil
        else { return "`\(file)`" }
        let lines = [finding.lineStart, finding.lineEnd].compactMap { $0 }
            .map(String.init).joined(separator: "-")
        return "`\(file):\(lines)` (\(finding.lineType.rawValue))"
    }

    /// Posted body = the finding's verbatim markdown plus a footer: the intended
    /// location when the note carries no diff anchor (`includeAnchor`), and
    /// cross-links to related findings. Returns the body and the link ids that
    /// resolved to a thread URL (the rest stay bare ids until their thread
    /// exists — the publish second pass fills them in).
    private static func renderedBody(
        for finding: Finding, ledger: PublishLedger, includeAnchor: Bool
    ) -> (body: String, resolved: [String]) {
        var resolved: [String] = []
        var footer: [String] = []
        if includeAnchor, let label = anchorLabel(for: finding) {
            footer.append("📍 \(label)")
        }
        if !finding.links.isEmpty {
            let parts = finding.links.map { id -> String in
                guard let url = ledger.url(for: id) else { return id }
                resolved.append(id)
                return "[\(id)](\(url))"
            }
            footer.append("🔗 " + parts.joined(separator: " · "))
        }
        guard !footer.isEmpty else { return (finding.markdown, []) }
        return (finding.markdown + "\n\n" + footer.joined(separator: "\n"), resolved)
    }
}
