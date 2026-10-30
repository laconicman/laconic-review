import Foundation
import GitLabKit
import GitLabOpenAPI
import OpenAPIRuntime

/// The single GitLab-aware seam.
///
/// Everything provider-specific lives here; the rest of `LaconicReviewCore` and the whole CLI
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
        try await rawDiscussions(iid: iid).compactMap(Self.discussion)
    }

    /// The same endpoint as ``discussions(iid:)``, mapped to full threads — every non-system
    /// note body verbatim, with author and diff anchor. This is what `fetch` hands to an agent.
    public func threads(iid: Int) async throws -> [DiscussionThread] {
        try await rawDiscussions(iid: iid).compactMap(Self.thread)
    }

    /// `GET /projects/:id/merge_requests/:iid/discussions`, unmapped — all pages.
    /// GitLab paginates at 20 by default; without paging, threads past the first
    /// page would silently never reach the inbox.
    private func rawDiscussions(iid: Int) async throws -> [Components.Schemas.APIEntitiesDiscussion] {
        var all: [Components.Schemas.APIEntitiesDiscussion] = []
        var page = 1
        while true {
            let output = try await client.getApiV4ProjectsIdMergeRequestsNoteableIdDiscussions(
                .init(
                    path: .init(id: project, noteableId: iid),   // notes/discussions: id is a String
                    query: .init(page: page, perPage: 100)
                )
            )
            let batch = try output.ok.body.json
            all += batch
            if batch.count < 100 { return all }
            page += 1
        }
    }

    // MARK: - Writes

    /// `POST /projects/:id/merge_requests/:iid/discussions` — create a thread.
    ///
    /// Pass `position` **and** `diffRefs` for a line-anchored thread; omit either for a general
    /// note. `diffRefs` is the server's truth for `position`, fetched fresh via ``mergeRequest(iid:)``.
    public func postDiscussion(
        iid: Int, body: String, position: Position?, diffRefs: DiffRefs?
    ) async throws -> PostedDiscussion {
        // Build the body via the stable operation type + inferred `.init`, so the unstable
        // generated `RequestBody<hash>` name never appears here (see the GitLabKit upstream note).
        typealias Op = Operations.PostApiV4ProjectsIdMergeRequestsNoteableIdDiscussions
        let payload: Op.Input.Body
        if let position, let diffRefs {
            payload = .json(.init(
                body: body,
                position: .init(
                    baseSha: diffRefs.baseSha,
                    startSha: diffRefs.startSha,
                    headSha: diffRefs.headSha,
                    positionType: .text,
                    newPath: position.lineType == .new ? position.file : nil,
                    newLine: position.lineType == .new ? position.line : nil,
                    oldPath: position.lineType == .old ? position.file : nil,
                    oldLine: position.lineType == .old ? position.line : nil
                )
            ))
        } else {
            payload = .json(.init(body: body))
        }
        let discussion = try await client.postApiV4ProjectsIdMergeRequestsNoteableIdDiscussions(
            .init(path: .init(id: project, noteableId: iid), body: payload)
        ).created.body.json
        return PostedDiscussion(
            discussionID: discussion.id ?? "",
            noteID: discussion.notes?.first?.id.map(Int.init)
        )
    }

    /// `POST /projects/:id/merge_requests/:iid/discussions/:discussionId/notes` — reply in a thread.
    public func postNote(iid: Int, discussionID: String, body: String) async throws -> PostedDiscussion {
        let note = try await client.postApiV4ProjectsIdMergeRequestsNoteableIdDiscussionsDiscussionIdNotes(
            .init(
                path: .init(id: project, noteableId: iid, discussionId: discussionID),
                body: .json(.init(body: body))
            )
        ).created.body.json
        return PostedDiscussion(discussionID: discussionID, noteID: note.id.map { Int($0) })
    }

    /// `PUT /projects/:id/merge_requests/:iid/discussions/:discussionId` — resolve/unresolve.
    public func resolveThread(iid: Int, discussionID: String, resolved: Bool) async throws {
        _ = try await client.putApiV4ProjectsIdMergeRequestsNoteableIdDiscussionsDiscussionId(
            .init(
                path: .init(id: project, noteableId: iid, discussionId: discussionID),
                body: .json(.init(resolved: resolved))
            )
        ).ok
    }

    /// `PUT /projects/:id/merge_requests/:iid/discussions/:discussionId/notes/:noteId` — edit a
    /// note's body. Used by the publish second pass to rewrite `links=` into resolved thread URLs.
    public func updateNote(iid: Int, discussionID: String, noteID: Int, body: String) async throws {
        _ = try await client.putApiV4ProjectsIdMergeRequestsNoteableIdDiscussionsDiscussionIdNotesNoteId(
            .init(
                path: .init(id: project, noteableId: iid, discussionId: discussionID, noteId: noteID),
                body: .json(.init(body: body))
            )
        ).ok
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

    private static func thread(_ d: Components.Schemas.APIEntitiesDiscussion) -> DiscussionThread? {
        let allNotes = d.notes ?? []
        guard !allNotes.isEmpty, !allNotes.allSatisfy({ $0.system == true }) else { return nil }
        let notes = allNotes.filter { $0.system != true }.map(Self.threadNote)
        return DiscussionThread(
            id: d.id ?? "",
            individualNote: d.individualNote ?? false,
            resolvable: d.resolvable ?? allNotes.contains { $0.resolvable == true },
            resolved: d.resolved ?? allNotes.contains { $0.resolved == true },
            notes: notes
        )
    }

    private static func threadNote(_ n: Components.Schemas.APIEntitiesNote) -> ThreadNote {
        ThreadNote(
            id: n.id ?? -1,
            author: n.author?.name ?? "",
            username: n.author?.username ?? "",
            createdAt: n.createdAt,
            body: n.body ?? "",
            position: Self.position(n.position)
        )
    }

    /// GitLab ships `position` as an untyped object — pull new/old path+line out of the
    /// container (`new_path`+`new_line` win over `old_*`; GitLab sets both sides on a new line).
    private static func position(_ container: OpenAPIObjectContainer?) -> Position? {
        // `value` is `[String: (any Sendable)?]` — subscripting yields a double-optional.
        func unwrap(_ key: String) -> (any Sendable)? {
            guard let raw = container?.value[key], let v = raw else { return nil }
            return v
        }
        func int(_ key: String) -> Int? {
            switch unwrap(key) {
            case let i as Int: return i
            case let i64 as Int64: return Int(i64)
            case let d as Double: return Int(d)
            case let s as String: return Int(s)
            default: return nil
            }
        }
        if let file = unwrap("new_path") as? String, let line = int("new_line") {
            return Position(file: file, line: line, lineType: .new)
        }
        if let file = unwrap("old_path") as? String, let line = int("old_line") {
            return Position(file: file, line: line, lineType: .old)
        }
        // File-level comment (`position_type: "file"`): a path but no line — keep the
        // file name rather than dropping the anchor to `general`.
        if let file = (unwrap("new_path") ?? unwrap("old_path")) as? String {
            return Position(file: file, line: nil, lineType: .file)
        }
        return nil
    }
}
