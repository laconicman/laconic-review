import ArgumentParser
import Foundation
import LaconicReviewCore

/// Resolve (or unresolve) a published finding's MR discussion thread.
///
/// Looks the finding up in `<N>.published.json` to find its discussion id. Dry-run by default;
/// pass `--confirm` to actually update GitLab.
struct ResolveThreadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resolve-thread",
        abstract: "Mark a published finding's MR thread resolved (dry-run unless --confirm)."
    )

    @Argument(help: "Path to the review report markdown (locates the publish ledger).")
    var report: String

    @Argument(help: "Finding id to resolve (e.g. C1) — must already be published.")
    var finding: String

    @Flag(help: "Unresolve instead of resolve.")
    var unresolve = false

    @Flag(help: "Actually update GitLab. Without it, prints the plan (dry-run).")
    var confirm = false

    @OptionGroup var options: ConnectionOptions

    func run() async throws {
        let reportURL = URL(fileURLWithPath: report)
        let header = try ReportParser.parse(try String(contentsOf: reportURL, encoding: .utf8)).header
        let ledger = try PublishLedger.load(from: PublishLedger.url(forReport: reportURL))

        guard let thread = ledger.thread(for: finding) else {
            throw ValidationError("Finding \(finding) isn't in the publish ledger — run `publish --confirm` first.")
        }
        let resolved = !unresolve
        let verb = resolved ? "resolve" : "unresolve"

        guard confirm else {
            print("DRY RUN — would \(verb) \(finding) (discussion \(thread.discussionID)) on MR !\(header.iid). Re-run with --confirm.")
            return
        }
        try await options.makeConnection().resolveThread(
            iid: header.iid, discussionID: thread.discussionID, resolved: resolved
        )
        print("✓ \(verb)d \(finding) (\(thread.url ?? thread.discussionID))")
    }
}
