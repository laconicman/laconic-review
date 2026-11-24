import Foundation

/// Which forge a ``HostConfig`` points at. Detected from the `git remote` host (with a
/// `--host` override), never guessed per-call.
public enum ReviewHostKind: String, Sendable, Codable, Equatable {
    case gitlab
    case github
}

/// The provider seam: everything the CLI needs from a forge, expressed in the neutral DTOs
/// of ``Models``. `GitLabConnection` and `GitHubConnection` (each in its own target) are the
/// conformers; commands depend on `any ReviewHost` and never see a concrete client.
///
/// Two members are deliberately *not* symmetric across hosts — the protocol keeps the GitLab
/// vocabulary where the neutral model already does, and each host translates internally:
///
/// - `postDiscussion`/`postNote` take a ``ResolvedPosition`` — the diff-side coordinate pair
///   (`old_*`/`new_*` line numbers). GitLab sends it as `position`; GitHub maps it to
///   `path` + `line` + `side` (`RIGHT` = new, `LEFT` = old).
/// - `discussionID` is opaque: a GitLab discussion id on one host, a GitHub review-thread
///   node id (`PRRT_…`) or issue-comment node id (`IC_…`) on the other. Whatever
///   `postDiscussion` returns is what `postNote`/`resolveThread`/`updateNote` accept back.
public protocol ReviewHost: Sendable {
    /// Which forge this connection talks to — drives host-specific labels (`MR !` vs `PR #`).
    var kind: ReviewHostKind { get }

    // MARK: - Reads

    /// The token's identity (`GET /user` on both hosts).
    func currentUser() async throws -> Identity

    /// Every MR/PR for a source branch (any state).
    func mergeRequests(sourceBranch: String) async throws -> [MergeRequestSummary]

    /// MR/PR metadata plus the SHAs a line comment anchors to (GitLab `diff_refs`;
    /// GitHub `base.sha`/`head.sha` — `startSha` stays `nil` there).
    func mergeRequest(iid: Int) async throws -> (summary: MergeRequestSummary, diffRefs: DiffRefs)

    /// Non-system review threads, full note bodies — what `fetch` hands to an agent.
    func threads(iid: Int) async throws -> [DiscussionThread]

    /// The same threads reduced to publish-relevant shape — the `discussions` listing.
    func discussions(iid: Int) async throws -> [DiscussionSummary]

    /// Every changed file's unified diff — publish resolves line anchors against these.
    func mergeRequestDiffs(iid: Int) async throws -> [FileDiff]

    // MARK: - Writes

    /// Create a thread: pass a ``ResolvedPosition`` **and** `diffRefs` for a line-anchored
    /// thread; pass `nil` for a general note. `diffRefs` is the server's truth for the
    /// anchor's base commit, fetched fresh via ``mergeRequest(iid:)``.
    func postDiscussion(
        iid: Int, body: String, position: ResolvedPosition?, diffRefs: DiffRefs?
    ) async throws -> PostedDiscussion

    /// Reply inside an existing thread. Hosts without threaded general comments reject
    /// ids that don't name a real thread.
    func postNote(iid: Int, discussionID: String, body: String) async throws -> PostedDiscussion

    /// Resolve/unresolve a thread. Only meaningful for resolvable threads — general
    /// comments on hosts without resolvable general comments will fail.
    func resolveThread(iid: Int, discussionID: String, resolved: Bool) async throws

    /// Edit a posted note's body — the publish second pass rewrites `links=` into
    /// resolved thread URLs. `noteID` is the ``PostedDiscussion/noteID`` first posted.
    func updateNote(iid: Int, discussionID: String, noteID: Int, body: String) async throws

    // MARK: - Host-specific policy

    /// Whether a failed ``postDiscussion`` may be retried as a general note — only for a
    /// *definite* rejection of an inferred out-of-hunk anchor (GitLab: HTTP 400; GitHub:
    /// HTTP 422). Transport errors and other statuses are ambiguous: the post may already
    /// have committed, and a retry could double-post.
    func shouldFallbackToGeneralNote(error: Error, anchor: ResolvedPosition?) -> Bool

    /// Permalink to a posted note. `mergeRequestWebURL` is the MR/PR's `webURL` — hosts
    /// whose API returns permalinks (GitHub `html_url`) use ``PostedDiscussion/url``;
    /// GitLab composes its `#note_<id>` fragment from the MR URL.
    func noteURL(for posted: PostedDiscussion, mergeRequestWebURL: String?) -> String?
}
