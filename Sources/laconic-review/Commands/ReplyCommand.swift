import ArgumentParser
import Foundation
import LaconicReviewCore

/// Post a note into an existing MR discussion thread, optionally resolving it.
///
/// The resolution reply should name the fix (commit, file) — it is the signal that lets a
/// reader distinguish "the author claims this is fixed" from "the asker confirmed it".
/// Dry-run unless `--confirm`.
struct ReplyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reply",
        abstract: "Reply in an existing MR discussion thread (dry-run unless --confirm)."
    )

    @Argument(help: "Merge request iid.")
    var iid: Int

    @Argument(help: "Discussion id (see `fetch` / `discussions`).")
    var discussionID: String

    @Option(help: "Reply text (markdown). Mutually exclusive with --body-file.")
    var body: String?

    @Option(name: .customLong("body-file"), help: "Read reply text from a file, or '-' for stdin.")
    var bodyFile: String?

    @Flag(help: "Resolve the thread after posting.")
    var resolve = false

    @Flag(help: "Unresolve the thread after posting.")
    var unresolve = false

    @Flag(help: "Actually post to GitLab. Without it, prints the plan (dry-run).")
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
        let text = try replyBody()
        guard !(resolve && unresolve) else {
            throw ValidationError("Pick one of --resolve / --unresolve, not both.")
        }
        let suffix = resolve ? " and resolve it" : (unresolve ? " and unresolve it" : "")

        guard confirm else {
            print("DRY RUN — would post \(text.count) chars to discussion \(discussionID) on MR !\(iid)\(suffix). Re-run with --confirm.")
            return
        }

        let connection = try options.makeConnection()
        let posted = try await connection.postNote(iid: iid, discussionID: discussionID, body: text)
        if resolve || unresolve {
            try await connection.resolveThread(iid: iid, discussionID: discussionID, resolved: resolve)
        }

        // The note permalink needs the MR's web_url — one extra read for a copyable result.
        let (mr, _) = try await connection.mergeRequest(iid: iid)
        let url = posted.noteID.flatMap { id in mr.webURL.map { "\($0)#note_\(id)" } }
        print("✓ replied → \(url ?? discussionID)\(resolve ? " · resolved" : unresolve ? " · unresolved" : "")")
    }

    private func replyBody() throws -> String {
        switch (body, bodyFile) {
        case (let text?, nil):
            return text
        case (nil, let path?):
            if path == "-" {
                return String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
            }
            return try String(contentsOfFile: path, encoding: .utf8)
        case (.some, .some):
            throw ValidationError("Pass --body or --body-file, not both.")
        case (nil, nil):
            throw ValidationError("Reply needs text: --body \"…\" or --body-file <path|->.")
        }
    }
}
