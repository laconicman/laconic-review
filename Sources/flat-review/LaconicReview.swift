import ArgumentParser

/// `flat-review` — read (and, later, publish) code-review findings against a GitLab MR.
///
/// Phase 2.a ships the read-only commands; `publish` / `resolve-thread` follow once the
/// markdown report format is wired through.
@main
struct LaconicReview: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "flat-review",
        abstract: "Read and publish code-review findings to a GitLab merge request.",
        version: "0.1.0",
        subcommands: [
            WhoAmICommand.self,
            ResolveCommand.self,
            DiscussionsCommand.self,
            DiffRefsCommand.self,
        ]
    )
}
