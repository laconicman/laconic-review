import ArgumentParser
import GitHubConnection
import GitLabConnection
import LaconicReviewCore

/// Flags shared by every subcommand. The token is taken from the environment, never a flag.
struct ConnectionOptions: ParsableArguments {
    @Option(help: "Forge project: GitLab id/namespace path or GitHub owner/repo. Default: from `git remote`.")
    var project: String?

    @Option(name: .customLong("base-url"), help: "Forge base URL, scheme + host (e.g. https://gitlab.example.com). Default: from `git remote`.")
    var baseURL: String?

    @Option(help: "Forge host: gitlab or github. Default: detected from the base URL.")
    var host: ReviewHostKind?

    @Option(name: .customLong("token-env"), help: "Environment variable holding the access token. Default: GITLAB_TOKEN or GITHUB_TOKEN, per host.")
    var tokenEnv: String?

    @Flag(help: "Emit machine-readable JSON instead of text.")
    var json = false

    /// Resolves config (flags → `git remote` → token env) and opens a connection.
    /// Pass `requireProject: false` for project-less operations like `whoami` (`GET /user`).
    func makeConnection(requireProject: Bool = true) throws -> any ReviewHost {
        let config = try ProjectContext.resolve(
            project: project, baseURL: baseURL, tokenEnv: tokenEnv,
            host: host, requireProject: requireProject
        )
        switch config.kind {
        case .gitlab:
            return GitLabConnection(config: config)
        case .github:
            return try GitHubConnection(config: config)
        }
    }

    /// Offline forge detection for dry-run labels — no token or connection needed.
    func detectKind() -> ReviewHostKind {
        ProjectContext.detectKind(explicit: host, baseURL: baseURL)
    }
}

extension ReviewHostKind: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }
}
