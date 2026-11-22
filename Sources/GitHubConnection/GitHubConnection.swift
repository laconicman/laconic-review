import Foundation
import LaconicReviewCore

/// The GitHub-aware seam — the ``ReviewHost`` conformance for pull requests.
///
/// Everything provider-specific lives in this target (`GitHubClient` + the mapping below);
/// the rest of the package speaks only the neutral DTOs in ``Models``. When the GitHub API
/// shape changes, **this is the file to re-derive**.
///
/// Where GitHub doesn't map one-to-one onto the neutral model:
///
/// - **Threads are GraphQL node ids.** REST has no review-thread concept, so `threads`,
///   `postNote`, `resolveThread`, and the `PRRT_…` id that `postDiscussion` returns all go
///   through GraphQL. Issue comments (general notes) get their `IC_…`-style node id as the
///   discussion id — they can't be replied to in-thread or resolved, and the methods say so.
/// - **Anchors are `path` + `line` + `side`.** A ``ResolvedPosition``'s new side maps to
///   `side: RIGHT`, its old side to `LEFT`; context lines post on `RIGHT` at the new line,
///   same rule GitLab uses for its four-field position.
/// - **General findings are issue comments** — a different endpoint and id space from
///   review comments, exactly like the issue describes for GitLab's position-less notes.
public struct GitHubConnection: Sendable, ReviewHost {
    public var kind: ReviewHostKind { .github }

    private let client: GitHubClient

    public init(config: HostConfig) throws {
        self.client = try GitHubClient(config: config)
    }

    /// Test seam — injects a client with a stubbed transport.
    init(client: GitHubClient) {
        self.client = client
    }

    // MARK: - Reads

    /// `GET /user` — the token's identity.
    public func currentUser() async throws -> Identity {
        let user = try await client.user()
        return Identity(id: user.id, username: user.login, name: user.name)
    }

    /// `GET /repos/{o}/{r}/pulls?state=all` — every PR for a branch, any state.
    /// Filters client-side on `head.ref` so fork PRs resolve too.
    public func mergeRequests(sourceBranch: String) async throws -> [MergeRequestSummary] {
        try await client.pullRequests().compactMap { pr in
            pr.head.ref == sourceBranch ? Self.summary(pr) : nil
        }
    }

    /// `GET /repos/{o}/{r}/pulls/{n}` — PR metadata plus the anchor SHAs.
    /// GitHub has no `start_sha` equivalent here — `base.sha`/`head.sha` are what
    /// review comments need (`commit_id` = head).
    public func mergeRequest(iid: Int) async throws -> (summary: MergeRequestSummary, diffRefs: DiffRefs) {
        let pr = try await client.pullRequest(iid)
        return (
            Self.summary(pr),
            DiffRefs(baseSha: pr.base.sha, headSha: pr.head.sha, startSha: nil)
        )
    }

    /// Review threads (GraphQL) + issue comments (REST), full note bodies — what
    /// `fetch` hands to an agent. Issue comments become `individualNote` threads:
    /// standalone, unresolvable — the same shape GitLab gives a plain MR note.
    public func threads(iid: Int) async throws -> [DiscussionThread] {
        let reviewThreads = try await client.reviewThreads(iid).compactMap(Self.thread)
        let comments = try await client.issueComments(iid).map(Self.issueCommentThread)
        return reviewThreads + comments
    }

    /// The same threads reduced to publish-relevant shape — the `discussions` listing.
    public func discussions(iid: Int) async throws -> [DiscussionSummary] {
        try await threads(iid: iid).map(Self.summary)
    }

    /// `GET /repos/{o}/{r}/pulls/{n}/files` — every changed file's unified diff (`patch`).
    /// Files without a `patch` (binary, oversized) map to `tooLarge` — their anchors
    /// can't be trusted, so out-of-hunk inference demotes to general notes, same rule
    /// as GitLab's `too_large`.
    public func mergeRequestDiffs(iid: Int) async throws -> [FileDiff] {
        try await client.pullRequestFiles(iid).map {
            FileDiff(
                oldPath: $0.previous_filename ?? $0.filename,
                newPath: $0.filename,
                diff: $0.patch ?? "",
                newFile: $0.status == "added",
                deletedFile: $0.status == "removed",
                collapsed: false,
                tooLarge: $0.patch == nil
            )
        }
    }

    // MARK: - Writes

    /// A line anchor posts a review comment (`POST /pulls/{n}/comments`), then a GraphQL
    /// lookup resolves the `PRRT_…` thread id the ledger and `resolve-thread` need.
    /// A general finding posts an issue comment (`POST /issues/{n}/comments`).
    public func postDiscussion(
        iid: Int, body: String, position: ResolvedPosition?, diffRefs: DiffRefs?
    ) async throws -> PostedDiscussion {
        guard let position else {
            let comment = try await client.createIssueComment(iid, body: body)
            return PostedDiscussion(
                discussionID: comment.node_id, noteID: Int(comment.id), url: comment.html_url
            )
        }
        guard let headSHA = diffRefs?.headSha else {
            throw GitHubRequestError.missingHeadSHA
        }
        let anchor = try Self.anchor(position)
        let comment = try await client.createReviewComment(
            iid, body: body, commitID: headSHA,
            path: anchor.path, line: anchor.line, side: anchor.side
        )
        let threadID = try await client.threadID(forCommentDatabaseId: comment.id, pullRequest: iid)
        return PostedDiscussion(
            discussionID: threadID, noteID: Int(comment.id), url: comment.html_url
        )
    }

    /// Reply inside a review thread — GraphQL `addPullRequestReviewThreadReply`.
    /// Issue comments have no threads on GitHub; the id check says so plainly.
    public func postNote(iid: Int, discussionID: String, body: String) async throws -> PostedDiscussion {
        guard Self.isReviewThread(discussionID) else {
            throw GitHubRequestError.unsupportedOperation(
                "`\(discussionID)` isn't a GitHub review thread — issue comments have no threaded replies"
            )
        }
        let reply = try await client.addThreadReply(threadID: discussionID, body: body)
        return PostedDiscussion(
            discussionID: discussionID,
            noteID: reply.databaseId.map(Int.init),
            url: reply.url
        )
    }

    /// Resolve/unresolve a review thread — GraphQL only; REST has no equivalent.
    public func resolveThread(iid: Int, discussionID: String, resolved: Bool) async throws {
        guard Self.isReviewThread(discussionID) else {
            throw GitHubRequestError.unsupportedOperation(
                "`\(discussionID)` isn't a GitHub review thread — issue comments can't be resolved"
            )
        }
        try await client.setThreadResolved(threadID: discussionID, resolved: resolved)
    }

    /// Edit a note's body — review comments and issue comments are different REST
    /// endpoints, told apart by the discussion id's kind (`PRRT_…` vs issue comment).
    public func updateNote(iid: Int, discussionID: String, noteID: Int, body: String) async throws {
        if Self.isReviewThread(discussionID) {
            try await client.updateReviewComment(Int64(noteID), body: body)
        } else {
            try await client.updateIssueComment(Int64(noteID), body: body)
        }
    }

    // MARK: - ReviewHost policy

    /// GitHub's definite position rejection is HTTP 422 ("Validation Failed").
    public func shouldFallbackToGeneralNote(error: Error, anchor: ResolvedPosition?) -> Bool {
        guard anchor?.outsideHunks == true,
              let requestError = error as? GitHubRequestError,
              case .httpStatus(422, _) = requestError
        else { return false }
        return true
    }

    /// GitHub's API returns the permalink (`html_url`) with every comment — use it.
    public func noteURL(for posted: PostedDiscussion, mergeRequestWebURL: String?) -> String? {
        posted.url
    }

    // MARK: - Mapping (GitHub types → neutral DTOs)

    /// Review-thread node ids start with `PRRT_`; issue-comment node ids don't.
    /// The prefix is the whole kind check — `updateNote`/`postNote`/`resolveThread`
    /// dispatch on it.
    static func isReviewThread(_ discussionID: String) -> Bool {
        discussionID.hasPrefix("PRRT_")
    }

    static func summary(_ pr: GHPullRequest) -> MergeRequestSummary {
        MergeRequestSummary(
            iid: pr.number,
            state: pr.state == "open" ? .opened : (pr.merged_at != nil ? .merged : .closed),
            title: pr.title,
            sourceBranch: pr.head.ref,
            targetBranch: pr.base.ref,
            webURL: pr.html_url,
            updatedAt: date(pr.updated_at)
        )
    }

    static func thread(_ t: GHReviewThread) -> DiscussionThread? {
        let notes = t.comments.nodes.map { note($0, thread: t) }
        guard !notes.isEmpty else { return nil }
        return DiscussionThread(
            id: t.id, individualNote: false, resolvable: true,
            resolved: t.isResolved, notes: notes
        )
    }

    static func note(_ c: GHReviewThreadComment, thread t: GHReviewThread) -> ThreadNote {
        ThreadNote(
            id: c.databaseId,
            author: c.author?.login ?? "",
            username: c.author?.login ?? "",
            createdAt: date(c.createdAt),
            body: c.body,
            position: position(c, thread: t)
        )
    }

    /// A comment's diff anchor. `line` is null on outdated threads — `originalLine`
    /// keeps the line it was written against. Replies may carry no position fields
    /// at all; they inherit the thread's anchor — path/line from the thread, side
    /// from its first (anchoring) comment.
    static func position(_ c: GHReviewThreadComment, thread t: GHReviewThread) -> Position? {
        let file = c.path ?? t.path
        let line = c.line ?? c.originalLine ?? t.line ?? t.originalLine
        guard let file else { return nil }
        guard let line else { return Position(file: file, line: nil, lineType: .file) }
        let side = c.side ?? t.comments.nodes.first?.side
        return Position(file: file, line: line, lineType: side == "LEFT" ? .old : .new)
    }

    /// An issue comment as a standalone thread — GitHub's answer to a GitLab general note.
    static func issueCommentThread(_ c: GHIssueComment) -> DiscussionThread {
        DiscussionThread(
            id: c.node_id, individualNote: true, resolvable: false, resolved: false,
            notes: [ThreadNote(
                id: c.id, author: c.user?.login ?? "", username: c.user?.login ?? "",
                createdAt: date(c.created_at), body: c.body, position: nil
            )]
        )
    }

    static func summary(_ t: DiscussionThread) -> DiscussionSummary {
        DiscussionSummary(
            id: t.id,
            noteCount: t.notes.count,
            resolvable: t.resolvable,
            resolved: t.resolved,
            onDiff: t.position != nil,
            preview: t.notes.first.map { String($0.body.prefix(120)) }
        )
    }

    /// ``ResolvedPosition`` → GitHub's `(path, line, side)`. The new side wins when
    /// both coordinates exist (a context line posts on `RIGHT` at its new line —
    /// same convention as GitLab's four-field position).
    static func anchor(_ position: ResolvedPosition) throws -> (path: String, line: Int, side: String) {
        if let line = position.newLine {
            guard let path = position.newPath ?? position.oldPath else {
                throw GitHubRequestError.invalidAnchor("new line without a path")
            }
            return (path, line, "RIGHT")
        }
        if let line = position.oldLine {
            guard let path = position.oldPath ?? position.newPath else {
                throw GitHubRequestError.invalidAnchor("old line without a path")
            }
            return (path, line, "LEFT")
        }
        throw GitHubRequestError.invalidAnchor("position carries no line")
    }

    /// GitHub timestamps are ISO-8601, sometimes with fractional seconds.
    static func date(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
