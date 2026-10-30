import ArgumentParser
import Foundation
import LaconicReviewCore

/// Fetch every non-system review thread on an MR — full note bodies, authors, diff
/// anchors — into an anchored-markdown inbox file (or `--json` to stdout).
///
/// This is the *inbound* half of the loop the publish side already owns:
/// `fetch` → fix the code → `reply` in the thread → resolve it.
struct FetchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fetch",
        abstract: "Fetch full MR discussion threads into an inbox file (default .claude/reviews/<branch>/inbox-<iid>.md)."
    )

    @Argument(help: "Merge request iid.")
    var iid: Int

    @Option(help: "Inbox file path. Default: .claude/reviews/<mr-source-branch>/inbox-<iid>.md")
    var output: String?

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
        let connection = try options.makeConnection()
        let (mr, _) = try await connection.mergeRequest(iid: iid)
        let threads = try await connection.threads(iid: iid)
        let inbox = Inbox(
            iid: iid, title: mr.title, webURL: mr.webURL,
            branch: mr.sourceBranch, fetchedAt: Date(), threads: threads
        )

        if options.json {
            print(try JSON.string(inbox))
            return
        }

        let url = output.map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: ".claude/reviews/\(inbox.branch)/inbox-\(iid).md")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try InboxRenderer.render(inbox).write(to: url, atomically: true, encoding: .utf8)

        print("✓ \(url.path) — \(threads.count) thread(s), \(inbox.openCount) open, \(inbox.resolvedCount) resolved")
    }
}
