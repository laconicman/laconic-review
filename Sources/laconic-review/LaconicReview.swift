import ArgumentParser

/// `laconic-review` — read and publish code-review findings against a GitLab MR.
///
/// Read commands resolve/inspect an MR; `publish` posts a report's findings as discussions and
/// `resolve-thread` resolves them — both dry-run unless `--confirm`.
@main
struct LaconicReview: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "laconic-review",
        abstract: "Read and publish code-review findings to a GitLab merge request.",
        version: "0.1.0",
        subcommands: [
            WhoAmICommand.self,
            ResolveCommand.self,
            DiscussionsCommand.self,
            DiffRefsCommand.self,
            PublishCommand.self,
            ResolveThreadCommand.self,
        ]
    )
}
