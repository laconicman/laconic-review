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

        // Confirmed: diff_refs is the server's truth for `position`, fetched fresh now.
        let connection = try options.makeConnection()
        let (mr, diffRefs) = try await connection.mergeRequest(iid: iid)

        // Pass 1 — post every pending finding, recording its thread URL. Forward cross-links (to a
        // finding posted later in this pass) render as bare ids for now; pass 2 resolves them.
        var posted = 0
        for finding in pending {
            let (body, resolved) = Self.renderedBody(for: finding, ledger: ledger)
            let result = try await connection.postDiscussion(
                iid: iid, body: body, position: finding.position, diffRefs: diffRefs
            )
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

        print("\nPublished \(posted); relinked \(relinked); \(skipped) skipped. "
            + "Ledger: \(ledgerURL.lastPathComponent)")
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
