import Foundation
import LaconicReviewCore

/// Errors surfaced by the GitHub transport. `httpStatus` carries GitHub's `message`
/// field when the error body has one — it's what makes a 422 diagnosable.
public enum GitHubRequestError: Error, Equatable, CustomStringConvertible {
    /// Non-2xx response; `message` is GitHub's `message` field when present.
    case httpStatus(Int, String?)
    /// GraphQL `errors[]` entries, joined.
    case graphql(String)
    /// Response body didn't match the expected shape.
    case decodingFailed(String)
    /// `projectPath` isn't `owner/repo` — raised lazily by repo-scoped calls so
    /// project-less operations (`whoami`) still work.
    case invalidProjectPath(String)
    /// A line anchor was requested without a head SHA to anchor it to.
    case missingHeadSHA
    /// A `ResolvedPosition` that doesn't translate to GitHub's path/line/side.
    case invalidAnchor(String)
    /// The operation doesn't exist for this id kind on GitHub (e.g. resolving an
    /// issue comment, which has no thread).
    case unsupportedOperation(String)
    /// A review comment posted but its `PRRT_…` thread id couldn't be resolved —
    /// the comment is live on the PR; only the ledger link is missing. Detail
    /// carries the comment URL and the underlying failure.
    case threadLookupFailed(String)

    public var description: String {
        switch self {
        case .httpStatus(let code, let message):
            return "GitHub rejected the request (HTTP \(code))" + (message.map { " — \($0)" } ?? "")
        case .graphql(let message): return "GitHub GraphQL error — \(message)"
        case .decodingFailed(let detail): return "GitHub response didn't decode — \(detail)"
        case .invalidProjectPath(let path): return "GitHub project must be `owner/repo`, got `\(path)`"
        case .missingHeadSHA: return "no head SHA to anchor the comment to"
        case .invalidAnchor(let detail): return "anchor doesn't translate to a GitHub position — \(detail)"
        case .unsupportedOperation(let detail): return detail
        case .threadLookupFailed(let detail): return detail
        }
    }
}

/// Hand-written GitHub REST+GraphQL transport — the ~10 calls `GitHubConnection` needs,
/// no generated surface. REST covers reads and comment writes; GraphQL covers what REST
/// can't express: review threads with resolved state, thread replies, and
/// resolve/unresolve — all keyed by `PRRT_…` node ids.
struct GitHubClient: Sendable {
    /// REST root: `https://api.github.com`, `https://api.{tenant}.ghe.com` for
    /// data-residency tenants, or `{GHES}/api/v3`.
    let api: URL
    /// GraphQL endpoint — GHES mounts it at `/api/graphql`, *not* under the REST
    /// `/api/v3` root; `*.ghe.com` tenants serve it on the same `api.` host.
    let graphqlURL: URL
    let token: String
    /// `owner`/`repo` stay nil when `projectPath` isn't `owner/repo` (e.g. `whoami`
    /// runs project-less) — repo-scoped calls then throw ``invalidProjectPath``.
    let owner: String?
    let repo: String?
    /// The raw `projectPath`, kept for the ``invalidProjectPath`` error message.
    let projectPath: String
    /// One HTTP round-trip — `URLSession` in production; tests inject a stub.
    let send: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(config: HostConfig) {
        token = config.token
        projectPath = config.projectPath
        let host = config.baseURL.host?.lowercased() ?? ""
        if host == "github.com" {
            api = URL(string: "https://api.github.com")!
            graphqlURL = URL(string: "https://api.github.com/graphql")!
        } else if host.hasSuffix(".ghe.com") {
            // GitHub Enterprise Cloud with data residency: the API lives on
            // `api.{tenant}.ghe.com`, not on the tenant host itself.
            let apiHost = host.hasPrefix("api.") ? host : "api.\(host)"
            api = URL(string: "https://\(apiHost)")!
            graphqlURL = URL(string: "https://\(apiHost)/graphql")!
        } else {
            // GHES mounts REST under /api/v3 and GraphQL under /api/graphql.
            api = config.baseURL.appendingPathComponent("api/v3")
            graphqlURL = config.baseURL.appendingPathComponent("api/graphql")
        }
        let parts = config.projectPath.split(separator: "/", omittingEmptySubsequences: true)
        owner = parts.count == 2 ? String(parts[0]) : nil
        repo = parts.count == 2 ? String(parts[1]) : nil
        send = { try await URLSession.shared.data(for: $0) }
    }

    /// Test seam — same client, caller-supplied transport.
    init(api: URL, owner: String, repo: String, token: String,
         send: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.api = api
        self.graphqlURL = api.appendingPathComponent("graphql")
        self.owner = owner
        self.repo = repo
        self.projectPath = "\(owner)/\(repo)"
        self.token = token
        self.send = send
    }

    // MARK: - REST reads

    func user() async throws -> GHUser {
        try await request("GET", "user")
    }

    /// Every pull request, all pages — the caller filters by `head.ref`/`head.repo`,
    /// which catches fork PRs a `head=owner:branch` query would miss.
    func pullRequests() async throws -> [GHPullRequest] {
        try await paged(try repoPath("pulls"), query: [
            URLQueryItem(name: "state", value: "all"),
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "direction", value: "desc"),
        ])
    }

    func pullRequest(_ number: Int) async throws -> GHPullRequest {
        try await request("GET", try repoPath("pulls/\(number)"))
    }

    func pullRequestFiles(_ number: Int) async throws -> [GHPullRequestFile] {
        try await paged(try repoPath("pulls/\(number)/files"))
    }

    /// Submitted reviews — their bodies are the review-level summaries `threads`
    /// surfaces as standalone notes.
    func reviews(_ number: Int) async throws -> [GHReview] {
        try await paged(try repoPath("pulls/\(number)/reviews"))
    }

    func issueComments(_ number: Int) async throws -> [GHIssueComment] {
        try await paged(try repoPath("issues/\(number)/comments"))
    }

    // MARK: - REST writes

    /// `POST /issues/{n}/comments` — a general (non-anchored) note on the PR.
    func createIssueComment(_ number: Int, body: String) async throws -> GHIssueComment {
        try await request(
            "POST", try repoPath("issues/\(number)/comments"),
            body: GHCommentBody(body: body)
        )
    }

    /// `POST /pulls/{n}/comments` — a review comment anchored to `commitID`+`path`+`line`.
    /// Single-line only: `side` is `RIGHT` for new-side lines, `LEFT` for removed ones.
    func createReviewComment(
        _ number: Int, body: String, commitID: String, path: String, line: Int, side: String
    ) async throws -> GHReviewComment {
        try await request(
            "POST", try repoPath("pulls/\(number)/comments"),
            body: GHReviewCommentBody(body: body, commit_id: commitID, path: path, line: line, side: side)
        )
    }

    /// `PATCH /pulls/comments/{id}` — edit a review comment's body (publish pass 2).
    func updateReviewComment(_ id: Int64, body: String) async throws {
        let _: GHReviewComment = try await request(
            "PATCH", try repoPath("pulls/comments/\(id)"),
            body: GHCommentBody(body: body)
        )
    }

    /// `PATCH /issues/comments/{id}` — edit an issue comment's body.
    func updateIssueComment(_ id: Int64, body: String) async throws {
        let _: GHIssueComment = try await request(
            "PATCH", try repoPath("issues/comments/\(id)"),
            body: GHCommentBody(body: body)
        )
    }

    // MARK: - GraphQL

    /// All review threads with resolved state and comment bodies — `fetch`/`discussions`.
    /// Comments deeper than 100 in one thread aren't fetched (pathological; noted).
    func reviewThreads(_ number: Int) async throws -> [GHReviewThread] {
        let scope = try repoScope()
        var all: [GHReviewThread] = []
        var cursor: String? = nil
        while true {
            var variables: [String: JSONValue] = [
                "owner": .string(scope.owner), "repo": .string(scope.repo), "number": .int(number),
            ]
            if let cursor { variables["cursor"] = .string(cursor) }
            let page: GHThreadsData = try await graphql(Self.threadsQuery, variables: variables)
            guard let threads = page.repository?.pullRequest?.reviewThreads else {
                throw GitHubRequestError.httpStatus(404, "pull request #\(number)")
            }
            all += threads.nodes
            guard threads.pageInfo.hasNextPage, let next = threads.pageInfo.endCursor else { return all }
            cursor = next
        }
    }

    /// The `PRRT_…` node id of the thread a just-posted review comment started.
    /// A standalone `POST /pulls/{n}/comments` always opens a new thread whose first
    /// (only) comment is ours — match on the comment's node `id` (a string, immune to
    /// the GraphQL `Int` ceiling `databaseId` would hit). Walks *backward*
    /// (`last`/`before`) because the new thread is the newest: almost always the
    /// first page.
    func threadID(forCommentNodeID nodeID: String, pullRequest number: Int) async throws -> String {
        let scope = try repoScope()
        var cursor: String? = nil
        while true {
            var variables: [String: JSONValue] = [
                "owner": .string(scope.owner), "repo": .string(scope.repo), "number": .int(number),
            ]
            if let cursor { variables["before"] = .string(cursor) }
            let page: GHThreadIDsData = try await graphql(Self.threadIDsQuery, variables: variables)
            guard let threads = page.repository?.pullRequest?.reviewThreads else {
                throw GitHubRequestError.httpStatus(404, "pull request #\(number)")
            }
            for thread in threads.nodes where thread.firstCommentNodeID == nodeID {
                return thread.id
            }
            guard threads.pageInfo.hasPreviousPage, let start = threads.pageInfo.startCursor else {
                throw GitHubRequestError.decodingFailed("no review thread contains comment \(nodeID)")
            }
            cursor = start
        }
    }

    /// The PR number a `PRRT_…` thread lives on — `postNote`/`resolveThread` verify it
    /// against the caller's `iid` before mutating, since node ids are global across PRs.
    /// `nil` when the id isn't a review thread at all (e.g. an issue comment node).
    func threadPullRequestNumber(_ threadID: String) async throws -> Int? {
        struct Data: Decodable {
            struct Node: Decodable {
                struct PullRequest: Decodable { let number: Int }
                let pullRequest: PullRequest?
            }
            let node: Node?
        }
        let data: Data = try await graphql(Self.threadPRQuery, variables: ["id": .string(threadID)])
        return data.node?.pullRequest?.number
    }

    /// `addPullRequestReviewThreadReply` — reply inside a `PRRT_…` thread.
    func addThreadReply(threadID: String, body: String) async throws -> GHReplyComment {
        struct Data: Decodable {
            struct Payload: Decodable {
                struct Comment: Decodable {
                    let databaseId: Int64?
                    let url: String?
                }
                let comment: Comment?
            }
            let addPullRequestReviewThreadReply: Payload?
        }
        let data: Data = try await graphql(Self.replyMutation, variables: [
            "threadId": .string(threadID), "body": .string(body),
        ])
        return GHReplyComment(
            databaseId: data.addPullRequestReviewThreadReply?.comment?.databaseId,
            url: data.addPullRequestReviewThreadReply?.comment?.url
        )
    }

    /// `resolveReviewThread` / `unresolveReviewThread`.
    func setThreadResolved(threadID: String, resolved: Bool) async throws {
        struct Ack: Decodable {}
        let _: Ack = try await graphql(
            resolved ? Self.resolveMutation : Self.unresolveMutation,
            variables: ["threadId": .string(threadID)]
        )
    }

    // MARK: - Plumbing

    private static let threadsQuery = """
        query ReviewThreads($owner: String!, $repo: String!, $number: Int!, $cursor: String) {
          repository(owner: $owner, name: $repo) {
            pullRequest(number: $number) {
              reviewThreads(first: 100, after: $cursor) {
                pageInfo { hasNextPage endCursor hasPreviousPage startCursor }
                nodes {
                  id
                  isResolved
                  path
                  line
                  originalLine
                  diffSide
                  comments(first: 100) { nodes {
                    databaseId
                    body
                    createdAt
                    author { login }
                    path
                    line
                    originalLine
                  } }
                }
              }
            }
          }
        }
        """

    private static let threadIDsQuery = """
        query ThreadCommentIDs($owner: String!, $repo: String!, $number: Int!, $before: String) {
          repository(owner: $owner, name: $repo) {
            pullRequest(number: $number) {
              reviewThreads(last: 100, before: $before) {
                pageInfo { hasNextPage endCursor hasPreviousPage startCursor }
                nodes {
                  id
                  comments(first: 1) { nodes { id } }
                }
              }
            }
          }
        }
        """

    private static let threadPRQuery = """
        query ReviewThreadPR($id: ID!) {
          node(id: $id) {
            ... on PullRequestReviewThread { pullRequest { number } }
          }
        }
        """

    private static let replyMutation = """
        mutation ReplyToReviewThread($threadId: ID!, $body: String!) {
          addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $threadId, body: $body}) {
            comment { databaseId url }
          }
        }
        """

    private static let resolveMutation = """
        mutation ResolveReviewThread($threadId: ID!) {
          resolveReviewThread(input: {threadId: $threadId}) { thread { id isResolved } }
        }
        """

    private static let unresolveMutation = """
        mutation UnresolveReviewThread($threadId: ID!) {
          unresolveReviewThread(input: {threadId: $threadId}) { thread { id isResolved } }
        }
        """

    /// `repos/{owner}/{repo}/{suffix}` — throws ``invalidProjectPath`` when the
    /// config carried no usable project (`whoami` legitimately runs without one).
    private func repoPath(_ suffix: String) throws -> String {
        let scope = try repoScope()
        return "repos/\(scope.owner)/\(scope.repo)/\(suffix)"
    }

    private func repoScope() throws -> (owner: String, repo: String) {
        guard let owner, let repo else {
            throw GitHubRequestError.invalidProjectPath(projectPath)
        }
        return (owner, repo)
    }

    /// `owner/repo` as GitHub spells it — for matching `head.repo.full_name` on PRs.
    var repoFullName: String? {
        owner.flatMap { o in repo.map { "\(o)/\($0)" } }
    }

    /// `GET`/`POST`/`PATCH` against the REST API. Non-2xx → `.httpStatus` with GitHub's
    /// `message`; decode failure → `.decodingFailed`.
    private func request<Response: Decodable>(
        _ method: String, _ path: String,
        query: [URLQueryItem] = [], body: (any Encodable)? = nil
    ) async throws -> Response {
        var components = URLComponents(url: api, resolvingAgainstBaseURL: false)!
        components.path += "/" + path
        if !query.isEmpty { components.queryItems = query }
        return try await perform(method, url: components.url!, body: body)
    }

    /// One HTTP round-trip against an absolute URL — REST paths resolve against
    /// ``api``; GraphQL posts to ``graphqlURL`` (a different path on GHES).
    private func perform<Response: Decodable>(
        _ method: String, url: URL, body: (any Encodable)? = nil
    ) async throws -> Response {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        urlRequest.setValue("laconic-review", forHTTPHeaderField: "User-Agent")
        if let body {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        let (data, response) = try await send(urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubRequestError.decodingFailed("no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubRequestError.httpStatus(http.statusCode, Self.errorMessage(from: data))
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw GitHubRequestError.decodingFailed(String(describing: error))
        }
    }

    /// `POST` to ``graphqlURL`` — `data` on success, `.graphql` on `errors[]`.
    private func graphql<Response: Decodable>(
        _ query: String, variables: [String: JSONValue]
    ) async throws -> Response {
        let envelope: GraphQLEnvelope<Response> = try await perform(
            "POST", url: graphqlURL, body: GraphQLPayload(query: query, variables: variables)
        )
        if let errors = envelope.errors, !errors.isEmpty {
            throw GitHubRequestError.graphql(
                errors.compactMap(\.message).joined(separator: "; ")
            )
        }
        guard let data = envelope.data else {
            throw GitHubRequestError.decodingFailed("graphql returned no data")
        }
        return data
    }

    /// `per_page=100` paging — stops on the first short page, same contract as GitLab's.
    private func paged<Element: Decodable>(
        _ path: String, query: [URLQueryItem] = []
    ) async throws -> [Element] {
        var all: [Element] = []
        var page = 1
        while true {
            let batch: [Element] = try await request(
                "GET", path,
                query: query + [
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: "\(page)"),
                ]
            )
            all += batch
            if batch.count < 100 { return all }
            page += 1
        }
    }

    /// GitHub error bodies are `{message, errors?, documentation_url?}` — take `message`.
    private static func errorMessage(from data: Data) -> String? {
        struct ErrorBody: Decodable { let message: String? }
        return try? JSONDecoder().decode(ErrorBody.self, from: data).message
    }
}

// MARK: - Wire types (REST + GraphQL responses; internal to this target)

struct GHUser: Decodable {
    let id: Int64
    let login: String
    let name: String?
}

struct GHActor: Decodable {
    let login: String
}

struct GHPullRequest: Decodable {
    struct Branch: Decodable {
        let ref: String
        let sha: String
        /// `null` when the head fork was deleted — such PRs can't match a local branch.
        let repo: Repo?
    }
    /// Just enough of a repository to compare `full_name` (`owner/repo`).
    struct Repo: Decodable {
        let full_name: String
    }
    let number: Int
    let state: String
    let merged_at: String?
    let title: String
    let head: Branch
    let base: Branch
    let html_url: String
    let updated_at: String
}

struct GHPullRequestFile: Decodable {
    let filename: String
    let previous_filename: String?
    let patch: String?
    let status: String
}

struct GHIssueComment: Decodable {
    let id: Int64
    let node_id: String
    let body: String
    let created_at: String
    let html_url: String
    let user: GHActor?
}

struct GHReviewComment: Decodable {
    let id: Int64
    let node_id: String
    let html_url: String
}

/// `GET /pulls/{n}/reviews` — a submitted review; `body` is its review-level summary.
struct GHReview: Decodable {
    let id: Int64
    let node_id: String
    let body: String?
    let state: String
    let submitted_at: String?
    let user: GHActor?
}

struct GHCommentBody: Encodable {
    let body: String
}

struct GHReviewCommentBody: Encodable {
    let body: String
    let commit_id: String
    let path: String
    let line: Int
    let side: String
}

struct GHReplyComment {
    let databaseId: Int64?
    let url: String?
}

// GraphQL shapes — the queries above select exactly these fields.

struct GHPageInfo: Decodable {
    let hasNextPage: Bool
    let endCursor: String?
    let hasPreviousPage: Bool
    let startCursor: String?
}

struct GHConnection<T: Decodable>: Decodable {
    let pageInfo: GHPageInfo
    let nodes: [T]
}

/// `comments { nodes }` — first-N only, never paginated (deep threads are noted as truncated).
struct GHCommentNodes<T: Decodable>: Decodable {
    let nodes: [T]
}

struct GHReviewThread: Decodable {
    let id: String
    let isResolved: Bool
    let path: String?
    let line: Int?
    let originalLine: Int?
    /// `LEFT`/`RIGHT` — the side the thread was anchored on. Lives on the thread:
    /// `PullRequestReviewComment` has no side field (verified against the schema).
    let diffSide: String?
    let comments: GHCommentNodes<GHReviewThreadComment>
}

struct GHReviewThreadComment: Decodable {
    let databaseId: Int64
    let body: String
    let createdAt: String
    let author: GHActor?
    let path: String?
    let line: Int?
    let originalLine: Int?
}

struct GHThreadsData: Decodable {
    struct Repository: Decodable {
        struct PullRequest: Decodable {
            let reviewThreads: GHConnection<GHReviewThread>
        }
        let pullRequest: PullRequest?
    }
    let repository: Repository?
}

struct GHThreadNodeID: Decodable {
    let id: String
    let comments: GHCommentNodes<GHThreadCommentID>

    /// The thread's first comment's node id — our just-posted comment opens the thread.
    var firstCommentNodeID: String? { comments.nodes.first?.id }
}

struct GHThreadCommentID: Decodable {
    let id: String
}

struct GHThreadIDsData: Decodable {
    struct Repository: Decodable {
        struct PullRequest: Decodable {
            let reviewThreads: GHConnection<GHThreadNodeID>
        }
        let pullRequest: PullRequest?
    }
    let repository: Repository?
}

/// `{query, variables}` request body for `POST /graphql`.
private struct GraphQLPayload: Encodable {
    let query: String
    let variables: [String: JSONValue]
}

/// `{data, errors?}` wrapper around every GraphQL response.
private struct GraphQLEnvelope<T: Decodable>: Decodable {
    struct GraphQLError: Decodable { let message: String? }
    let data: T?
    let errors: [GraphQLError]?
}

/// `Encodable` existential box — `JSONEncoder` can't encode `any Encodable` directly.
private struct AnyEncodable: Encodable {
    let wrapped: any Encodable
    init(_ wrapped: any Encodable) { self.wrapped = wrapped }
    func encode(to encoder: Encoder) throws { try wrapped.encode(to: encoder) }
}

/// Minimal JSON value for GraphQL variables (strings and ints today; absent
/// optional variables are simply omitted from the dictionary).
enum JSONValue: Encodable {
    case string(String)
    case int(Int)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        }
    }
}
