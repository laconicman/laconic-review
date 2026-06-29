import ArgumentParser
import FlatReviewCore

/// Resolve the merge request for a branch via the decision tree → an iid, `none`, or candidates.
struct ResolveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resolve",
        abstract: "Resolve the merge request for a branch (one open MR → its iid; else candidates)."
    )

    @Argument(help: "Source branch to resolve.")
    var branch: String

    @Option(name: .customLong("base"), help: "Base branch the MR targets.")
    var base: String = "develop"

    @OptionGroup var options: ConnectionOptions

    func run() async throws {
        let mergeRequests = try await options.makeConnection().mergeRequests(sourceBranch: branch)
        let resolution = MergeRequestResolver.resolve(branch: branch, base: base, mergeRequests: mergeRequests)

        if options.json {
            print(try JSON.string(resolution))
            return
        }

        switch resolution {
        case .resolved(let iid):
            print("✓ MR !\(iid)")
        case .none:
            print("no-mr (pre-MR review)")
        case .ambiguous(let reason, let candidates):
            print("ambiguous: \(reason.rawValue)")
            for mr in candidates {
                print("  !\(mr.iid)  \(mr.title)")
            }
            if candidates.isEmpty { print("  (no open MRs)") }
        }
    }
}
