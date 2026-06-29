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

        var posted = 0
        for finding in pending {
            let result = try await connection.postDiscussion(
                iid: iid,
                body: Self.body(for: finding, ledger: ledger),
                position: finding.position,
                diffRefs: diffRefs
            )
            let url = result.noteID.flatMap { id in mr.webURL.map { "\($0)#note_\(id)" } }
            ledger.record(finding.id, PublishedThread(
                discussionID: result.discussionID, noteID: result.noteID, url: url
            ))
            try ledger.save(to: ledgerURL)   // incremental write — crash-safe across the loop
            posted += 1
            print("  ✓ \(finding.id) → \(url ?? result.discussionID)")
        }
        print("\nPublished \(posted); \(skipped) skipped. Ledger: \(ledgerURL.lastPathComponent)")
    }

    /// A human-readable anchor for the dry-run plan.
    private static func location(_ f: Finding) -> String {
        guard f.scope == .line else { return "general" }
        let lines = [f.lineStart, f.lineEnd].compactMap { $0 }.map(String.init).joined(separator: "-")
        return "\(f.file ?? "?"):\(lines) [\(f.lineType.rawValue)]"
    }

    /// Posted body = the finding's verbatim markdown plus a footer cross-linking related
    /// findings (linked to their thread URL once that finding is in the ledger; bare id until then).
    private static func body(for finding: Finding, ledger: PublishLedger) -> String {
        guard !finding.links.isEmpty else { return finding.markdown }
        let related = finding.links.map { id in ledger.url(for: id).map { "[\(id)](\($0))" } ?? id }
        return finding.markdown + "\n\n---\n_Related: \(related.joined(separator: ", "))_"
    }
}
