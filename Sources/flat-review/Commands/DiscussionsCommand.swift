import ArgumentParser
import FlatReviewCore

/// List the existing non-system review threads on an MR (idempotency input for publish).
struct DiscussionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "discussions",
        abstract: "List non-system discussion threads on a merge request."
    )

    @Argument(help: "Merge request iid.")
    var iid: Int

    @OptionGroup var options: ConnectionOptions

    func run() async throws {
        let threads = try await options.makeConnection().discussions(iid: iid)
        if options.json {
            print(try JSON.string(threads))
            return
        }
        guard !threads.isEmpty else { print("(no non-system threads)"); return }
        for thread in threads {
            let kind = thread.onDiff ? "diff" : "general"
            let state = thread.resolved ? "✅" : (thread.resolvable ? "⏳" : "—")
            print("\(state) [\(kind)] \(thread.id)  (\(thread.noteCount) notes)  \(thread.preview ?? "")")
        }
    }
}
