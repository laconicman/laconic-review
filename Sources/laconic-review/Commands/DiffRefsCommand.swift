import ArgumentParser
import LaconicReviewCore

/// Show the base/head/start SHAs for an MR — the refs a line comment anchors to.
struct DiffRefsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diff-refs",
        abstract: "Print base/head/start SHAs (the line-anchor refs) for a merge request."
    )

    @Argument(help: "Merge request iid.")
    var iid: Int

    @OptionGroup var options: ConnectionOptions

    func run() async throws {
        let (_, refs) = try await options.makeConnection().mergeRequest(iid: iid)
        if options.json {
            print(try JSON.string(refs))
            return
        }
        print("base_sha:  \(refs.baseSha ?? "—")")
        print("head_sha:  \(refs.headSha ?? "—")")
        print("start_sha: \(refs.startSha ?? "—")")
    }
}
