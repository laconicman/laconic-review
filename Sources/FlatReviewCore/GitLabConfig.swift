import Foundation

/// Connection coordinates: where the GitLab instance lives, which project, and the token.
///
/// `baseURL` is the API **root** (scheme + host [+ port]); the GitLab operations append
/// `/api/v4/...` themselves. `projectID` is either a numeric id or a namespace path
/// (e.g. `FP/partner-ios`) — both are accepted by GitLab's `:id` path parameter.
public struct GitLabConfig: Sendable {
    public let baseURL: URL
    public let projectID: String
    public let token: String

    public init(baseURL: URL, projectID: String, token: String) {
        self.baseURL = baseURL
        self.projectID = projectID
        self.token = token
    }
}

/// Resolves a ``GitLabConfig`` from explicit values, falling back to the repository's
/// `git remote` and an environment variable for the token.
///
/// Resolution order for base URL and project: explicit argument → parsed `origin` remote.
/// The token is **only** ever read from the environment — never passed as an argument.
public enum ProjectContext {
    /// - Parameters:
    ///   - project: Explicit project id/path, or `nil` to infer from `git remote`.
    ///   - baseURL: Explicit base URL, or `nil` to infer from `git remote`.
    ///   - tokenEnv: Name of the environment variable holding the access token.
    ///   - directory: Repository directory to inspect (defaults to the current directory).
    public static func resolve(
        project: String?,
        baseURL: String?,
        tokenEnv: String,
        requireProject: Bool = true,
        in directory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws -> GitLabConfig {
        guard let token = ProcessInfo.processInfo.environment[tokenEnv], !token.isEmpty else {
            throw ConnectionError.missingToken(env: tokenEnv)
        }

        // Only shell out to git if we actually need something from the remote. `whoami`
        // (GET /user) needs no project, so it passes `requireProject: false`.
        let needsRemote = baseURL == nil || (project == nil && requireProject)
        let remote = needsRemote ? try? gitRemote(in: directory) : nil

        guard let baseString = baseURL ?? remote?.baseURL, let url = URL(string: baseString) else {
            throw ConnectionError.cannotResolveBaseURL
        }
        guard let projectID = project ?? remote?.projectPath ?? (requireProject ? nil : "") else {
            throw ConnectionError.cannotResolveProject
        }
        return GitLabConfig(baseURL: url, projectID: projectID, token: token)
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
            var base = "\(scheme)://\(host)"
            if let port = url.port { base += ":\(port)" }
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

/// Errors raised while resolving configuration or talking to GitLab.
public enum ConnectionError: Error, CustomStringConvertible, Equatable {
    case missingToken(env: String)
    case cannotResolveBaseURL
    case cannotResolveProject

    public var description: String {
        switch self {
        case .missingToken(let env):
            return "No access token in environment variable `\(env)`. Export it (e.g. in ~/.zshenv) and retry."
        case .cannotResolveBaseURL:
            return "Could not determine the GitLab base URL. Pass --base-url or run inside a git repo with an `origin` remote."
        case .cannotResolveProject:
            return "Could not determine the GitLab project. Pass --project or run inside a git repo with an `origin` remote."
        }
    }
}
