import Foundation

/// Connection coordinates: which forge, where it lives, which project, and the token.
///
/// `baseURL` is the site root (scheme + host [+ port]) — each host connection turns it into
/// its API root (`/api/v4` for GitLab is appended by the generated operations; GitHub maps
/// `github.com` → `api.github.com` and GHES → `/api/v3`). `projectPath` is whatever the
/// host calls a project: a GitLab namespace path or numeric id, a GitHub `owner/repo`.
public struct HostConfig: Sendable {
    public let kind: ReviewHostKind
    public let baseURL: URL
    public let projectPath: String
    public let token: String

    public init(kind: ReviewHostKind, baseURL: URL, projectPath: String, token: String) {
        self.kind = kind
        self.baseURL = baseURL
        self.projectPath = projectPath
        self.token = token
    }
}

/// Resolves a ``HostConfig`` from explicit values, falling back to the repository's
/// `git remote` and an environment variable for the token.
///
/// The forge is picked by `--host` when given, else by the effective base URL's host:
/// GitHub's known hostnames map to `.github`, everything else stays `.gitlab` — the
/// historical default, so self-managed GitLab on an arbitrary domain keeps working and an
/// exotic GHES hostname just needs the override.
///
/// Resolution order for base URL and project: explicit argument → parsed `origin` remote.
/// The token is **only** ever read from the environment — never passed as an argument; its
/// variable defaults per host (`GITLAB_TOKEN` / `GITHUB_TOKEN`) unless `tokenEnv` overrides.
public enum ProjectContext {
    /// - Parameters:
    ///   - project: Explicit project id/path (`owner/repo` on GitHub), or `nil` to infer
    ///     from `git remote`.
    ///   - baseURL: Explicit base URL, or `nil` to infer from `git remote`.
    ///   - tokenEnv: Environment variable holding the access token, or `nil` for the
    ///     per-host default.
    ///   - host: `--host` override, or `nil` to detect from the base URL.
    ///   - directory: Repository directory to inspect (defaults to the current directory).
    public static func resolve(
        project: String?,
        baseURL: String?,
        tokenEnv: String?,
        host: ReviewHostKind?,
        requireProject: Bool = true,
        in directory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws -> HostConfig {
        // Only shell out to git if we actually need something from the remote. `whoami`
        // (GET /user) needs no project, so it passes `requireProject: false`.
        let needsRemote = baseURL == nil || (project == nil && requireProject)
        let remote = needsRemote ? try? gitRemote(in: directory) : nil

        guard let baseString = baseURL ?? remote?.baseURL, let url = URL(string: baseString) else {
            throw ConnectionError.cannotResolveBaseURL
        }
        let kind = ReviewHostKind.detect(explicit: host, baseURL: url)

        let env = tokenEnv ?? kind.defaultTokenEnv
        guard let token = ProcessInfo.processInfo.environment[env], !token.isEmpty else {
            throw ConnectionError.missingToken(env: env)
        }
        guard let projectPath = project ?? remote?.projectPath ?? (requireProject ? nil : "") else {
            throw ConnectionError.cannotResolveProject
        }
        return HostConfig(kind: kind, baseURL: url, projectPath: projectPath, token: token)
    }

    /// Best-effort forge detection for offline paths (dry-run labels) — same precedence as
    /// ``resolve(project:baseURL:tokenEnv:host:requireProject:in:)`` minus the token and
    /// project requirements: `--host`, then `--base-url`, then the `origin` remote.
    /// Unresolvable or unrecognized hosts fall back to `.gitlab`, the historical default.
    public static func detectKind(
        explicit host: ReviewHostKind?,
        baseURL: String?,
        in directory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> ReviewHostKind {
        if let host { return host }
        if let baseURL, let url = URL(string: baseURL) {
            return ReviewHostKind.detect(explicit: nil, baseURL: url)
        }
        guard let remote = try? gitRemote(in: directory),
              let url = URL(string: remote.baseURL) else { return .gitlab }
        return ReviewHostKind.detect(explicit: nil, baseURL: url)
    }

    // MARK: - git remote parsing

    struct ParsedRemote: Equatable {
        let baseURL: String
        let projectPath: String
    }

    private static func gitRemote(in directory: URL) throws -> ParsedRemote {
        let raw = try run(["git", "-C", directory.path, "remote", "get-url", "origin"])
        guard let parsed = parse(remote: raw) else { throw ConnectionError.cannotResolveBaseURL }
        return parsed
    }

    /// Parses both `http(s)://host[:port]/group/.../project[.git]` and the scp-like
    /// `git@host:group/project.git` remote forms into a base URL + namespace path.
    static func parse(remote: String) -> ParsedRemote? {
        var string = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasSuffix(".git") { string = String(string.dropLast(4)) }

        if let url = URL(string: string), let scheme = url.scheme, let host = url.host {
            // Only http(s) remotes carry a usable API base — ssh:// and friends get
            // https on the same host (their port is the SSH port, not the web one).
            let isWeb = scheme == "http" || scheme == "https"
            var base = "\(isWeb ? scheme : "https")://\(host)"
            if isWeb, let port = url.port { base += ":\(port)" }
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !path.isEmpty else { return nil }
            return ParsedRemote(baseURL: base, projectPath: path)
        }

        // scp-like: git@host:group/project
        if let at = string.firstIndex(of: "@"), let colon = string[at...].firstIndex(of: ":") {
            let host = String(string[string.index(after: at)..<colon])
            let path = String(string[string.index(after: colon)...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !host.isEmpty, !path.isEmpty else { return nil }
            return ParsedRemote(baseURL: "https://\(host)", projectPath: path)
        }
        return nil
    }

    private static func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension ReviewHostKind {
    /// The environment variable read when the caller doesn't name one.
    var defaultTokenEnv: String { self == .github ? "GITHUB_TOKEN" : "GITLAB_TOKEN" }

    /// `MR !965` on GitLab, `PR #965` on GitHub — the forge-appropriate target label.
    public func refLabel(_ iid: Int) -> String {
        self == .github ? "PR #\(iid)" : "MR !\(iid)"
    }

    /// Explicit `--host` wins; otherwise the base URL's host decides. GitHub hostnames
    /// map to `.github` when a DNS label is exactly `github` (`github.com`,
    /// `github.company.com`, `gist.github.com`) — substring matching would false-positive
    /// on `notgithub.com` — plus the `ghe.*`/`*.ghe.com` GHES conventions. Everything else
    /// stays `.gitlab`; an exotic GHES hostname needs `--host github`.
    static func detect(explicit: ReviewHostKind?, baseURL: URL) -> ReviewHostKind {
        if let explicit { return explicit }
        guard let host = baseURL.host?.lowercased() else { return .gitlab }
        if host.split(separator: ".").contains("github")
            || host.hasPrefix("ghe.") || host.hasSuffix(".ghe.com") {
            return .github
        }
        return .gitlab
    }
}

/// Errors raised while resolving configuration.
public enum ConnectionError: Error, CustomStringConvertible, Equatable {
    case missingToken(env: String)
    case cannotResolveBaseURL
    case cannotResolveProject

    public var description: String {
        switch self {
        case .missingToken(let env):
            return "No access token in environment variable `\(env)`. Export it (e.g. in ~/.zshenv) and retry."
        case .cannotResolveBaseURL:
            return "Could not determine the forge URL. Pass --base-url or run inside a git repo with an `origin` remote."
        case .cannotResolveProject:
            return "Could not determine the project. Pass --project or run inside a git repo with an `origin` remote."
        }
    }
}
