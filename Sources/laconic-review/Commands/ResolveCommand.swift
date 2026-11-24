import ArgumentParser
import LaconicReviewCore

/// Resolve the merge request / pull request for a branch via the decision tree → an iid,
/// `none`, or candidates.
struct ResolveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resolve",
        abstract: "Resolve the MR/PR for a branch (one open → its iid; else candidates)."
    )

    @Argument(help: "Source branch to resolve.")
    var branch: String

    @Option(name: .customLong("base"), help: "Base branch the MR/PR targets.")
    var base: String = "develop"

    @OptionGroup var options: ConnectionOptions

    func run() async throws {
        let connection = try options.makeConnection()
        let mergeRequests = try await connection.mergeRequests(sourceBranch: branch)
        let resolution = MergeRequestResolver.resolve(branch: branch, base: base, mergeRequests: mergeRequests)

        if options.json {
            print(try JSON.string(resolution))
            return
        }

        switch resolution {
        case .resolved(let iid):
            print("✓ \(refLabel(connection.kind, iid))")
        case .none:
            print("no-mr (pre-review)")
        case .ambiguous(let reason, let candidates):
            print("ambiguous: \(reason.rawValue)")
            for mr in candidates {
                print("  \(refLabel(connection.kind, mr.iid))  \(mr.title)")
            }
            if candidates.isEmpty { print("  (no open MRs/PRs)") }
        }
    }
}
