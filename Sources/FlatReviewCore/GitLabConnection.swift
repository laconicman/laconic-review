import Foundation
import GitLabKit
import GitLabOpenAPI

/// The single GitLab-aware seam.
///
/// Everything provider-specific lives here; the rest of `FlatReviewCore` and the whole CLI
/// speak only the neutral DTOs in ``Models``. When GitLabKit's API changes, **this is the one
/// file to re-derive** — read GitLabKit's (and this type's) DocC symbol graph, adjust the
/// mappings, done. That is the "self-heal" boundary.
///
/// The operation names are GitLab's verbose generated identifiers (see the GitLabKit README).
/// Note GitLab's own inconsistency, preserved by the generator: the **MR** operations type the
/// project `id` as an enum (`.case1(String)`), while the **notes/discussions** operations type
/// it as a plain `String`. Both forms appear below intentionally.
///
/// - Important: These call-sites were written against the GitLabKit README/handoff examples but
///   not compiled in this environment (GitLabKit is Darwin-only). On the first `swift build`,
///   expect to adjust exact field names / enum cases — all such risk is confined to this file.
public struct GitLabConnection: Sendable {
    private let client: Client
    private let project: String

    public init(config: GitLabConfig) {
        // Full base URL (http *or* https) via the `serverURL:` init added to GitLabKit.
        self.client = Client(token: config.token, serverURL: config.baseURL)
        self.project = config.projectID
    }

    // MARK: - Reads

    /// `GET /user` — the token's identity. (Needs `getApiV4User` in GitLabKit's review tier.)
    public func currentUser() async throws -> Identity {
        let user = try await client.getApiV4User().ok.body.json
        return Identity(id: user.id ?? -1, username: user.username ?? "", name: user.name)
    }

    /// `GET /projects/:id/merge_requests?source_branch=` — every MR for a branch (any state).
    public func mergeRequests(sourceBranch: String) async throws -> [MergeRequestSummary] {
        let output = try await client.getApiV4ProjectsIdMergeRequests(
            .init(
                path: .init(id: .case1(project)),
                query: .init(sourceBranch: sourceBranch)   // state omitted ⇒ GitLab returns all
            )
        )
        return try output.ok.body.json.map(Self.summary)
    }

    /// `GET /projects/:id/merge_requests/:iid` — MR metadata plus `diff_refs` (the anchor SHAs).
    public func mergeRequest(iid: Int) async throws -> (summary: MergeRequestSummary, diffRefs: DiffRefs) {
        let mr = try await client.getApiV4ProjectsIdMergeRequestsMergeRequestIid(
            .init(path: .init(id: .case1(project), mergeRequestIid: iid))
        ).ok.body.json
        let refs = DiffRefs(
            baseSha: mr.diffRefs?.baseSha,
            headSha: mr.diffRefs?.headSha,
            startSha: mr.diffRefs?.startSha
        )
        return (Self.summary(mr), refs)
    }

    /// `GET /projects/:id/merge_requests/:iid/discussions` — non-system threads only.
    ///
    /// Drops threads where every note is a system note (`'added 1 commit'`, etc.), matching
    /// the publish-side idempotency rule.
    public func discussions(iid: Int) async throws -> [DiscussionSummary] {
        let output = try await client.getApiV4ProjectsIdMergeRequestsNoteableIdDiscussions(
            .init(path: .init(id: project, noteableId: iid))   // notes/discussions: id is a String
        )
        return try output.ok.body.json.compactMap(Self.discussion)
    }

    // MARK: - Mapping (GitLab types → neutral DTOs)

    private static func summary(_ mr: Components.Schemas.APIEntitiesMergeRequest) -> MergeRequestSummary {
        MergeRequestSummary(
            iid: mr.iid ?? -1,
            state: MergeRequestState(rawValue: mr.state ?? "") ?? .unknown,
            title: mr.title ?? "",
            sourceBranch: mr.sourceBranch ?? "",
            targetBranch: mr.targetBranch ?? "",
            webURL: mr.webUrl,
            updatedAt: mr.updatedAt
        )
    }

    /// The list endpoint returns the *Basic* entity (a real GitLab spec distinction), with the
    /// same summary fields as the full one. A separate overload keeps each mapping explicit and
    /// directly tied to its GitLab type — easier for the skill to re-derive than a shared abstraction.
    private static func summary(_ mr: Components.Schemas.APIEntitiesMergeRequestBasic) -> MergeRequestSummary {
        MergeRequestSummary(
            iid: mr.iid ?? -1,
            state: MergeRequestState(rawValue: mr.state ?? "") ?? .unknown,
            title: mr.title ?? "",
            sourceBranch: mr.sourceBranch ?? "",
            targetBranch: mr.targetBranch ?? "",
            webURL: mr.webUrl,
            updatedAt: mr.updatedAt
        )
    }

    private static func discussion(_ d: Components.Schemas.APIEntitiesDiscussion) -> DiscussionSummary? {
        let notes = d.notes ?? []
        guard !notes.isEmpty, !notes.allSatisfy({ $0.system == true }) else { return nil }
        return DiscussionSummary(
            id: d.id ?? "",
            noteCount: notes.count,
            resolvable: notes.contains { $0.resolvable == true },
            resolved: notes.contains { $0.resolved == true },
            onDiff: notes.contains { $0.position != nil },
            preview: notes.first?.body.map { String($0.prefix(120)) }
        )
    }
}
