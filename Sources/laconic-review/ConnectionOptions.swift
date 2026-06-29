import ArgumentParser
import LaconicReviewCore

/// Flags shared by every subcommand. The token is taken from the environment, never a flag.
struct ConnectionOptions: ParsableArguments {
    @Option(help: "GitLab project: numeric id or namespace path (e.g. FP/partner-ios). Default: from `git remote`.")
    var project: String?

    @Option(name: .customLong("base-url"), help: "GitLab base URL, scheme + host (e.g. http://git.flat.lab). Default: from `git remote`.")
    var baseURL: String?

    @Option(name: .customLong("token-env"), help: "Environment variable holding the access token.")
    var tokenEnv: String = "GITLAB_TOKEN"

    @Flag(help: "Emit machine-readable JSON instead of text.")
    var json = false

    /// Resolves config (flags → `git remote` → token env) and opens a connection.
    /// Pass `requireProject: false` for project-less operations like `whoami` (`GET /user`).
    func makeConnection(requireProject: Bool = true) throws -> GitLabConnection {
        let config = try ProjectContext.resolve(
            project: project, baseURL: baseURL, tokenEnv: tokenEnv, requireProject: requireProject
        )
        return GitLabConnection(config: config)
    }
}
