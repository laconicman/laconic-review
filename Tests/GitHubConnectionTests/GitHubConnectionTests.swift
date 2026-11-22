import Foundation
@testable import GitHubConnection
import LaconicReviewCore
import XCTest

/// `GitHubConnection` against a stubbed transport: request shape (method, path,
/// headers, body) plus wire-JSON → neutral-DTO mapping. GraphQL calls all land on
/// `/graphql` — routed by operation-name substring inside the query text.
final class GitHubConnectionTests: XCTestCase {

    // MARK: - Stub transport

    /// Records every request; `handler` answers with (body, status).
    private final class Stub: @unchecked Sendable {
        private(set) var requests: [URLRequest] = []
        var handler: (URLRequest) throws -> (Data, Int)

        init(handler: @escaping (URLRequest) throws -> (Data, Int)) {
            self.handler = handler
        }

        func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
            requests.append(request)
            let (data, status) = try handler(request)
            return (data, HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
            )!)
        }
    }

    private enum StubError: Error { case unrouted(String) }

    private func connection(_ stub: Stub) -> GitHubConnection {
        GitHubConnection(client: GitHubClient(
            api: URL(string: "https://api.github.com")!,
            owner: "octo", repo: "repo", token: "tok",
            send: { try await stub.send($0) }
        ))
    }

    private func data(_ string: String) -> Data { Data(string.utf8) }
    private func ok(_ string: String) -> (Data, Int) { (data(string), 200) }

    /// Routes REST by "METHOD /path?query" substring and GraphQL by operation name.
    /// First matching route wins — order routes most-specific first.
    private func router(
        _ routes: [(match: String, response: (Data, Int))]
    ) -> (URLRequest) throws -> (Data, Int) {
        { request in
            let url = try XCTUnwrap(request.url)
            let target = url.path.hasSuffix("/graphql")
                ? self.graphqlOperation(of: request)
                : "\(request.httpMethod ?? "?") \(url.absoluteString.replacingOccurrences(of: "https://api.github.com", with: ""))"
            for route in routes where target.contains(route.match) {
                return route.response
            }
            throw StubError.unrouted(target)
        }
    }

    private func graphqlOperation(of request: URLRequest) -> String {
        guard let body = request.httpBody,
              let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let query = payload["query"] as? String
        else { return "graphql:?" }
        // "query ReviewThreads(" / "mutation ResolveReviewThread(" → "ReviewThreads"/"ResolveReviewThread"
        for keyword in ["query ", "mutation "] {
            if let range = query.range(of: keyword) {
                let rest = query[range.upperBound...]
                return String(rest.prefix { $0.isLetter })
            }
        }
        return "graphql:?"
    }

    private func requestBody(_ request: URLRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]) ?? [:]
    }

    // MARK: - Fixtures

    private func pullRequestJSON(
        number: Int = 7, state: String = "open", mergedAt: String? = nil,
        headRef: String = "feat/x", headSha: String = "headsha", baseSha: String = "basesha"
    ) -> String {
        let merged = mergedAt.map { "\"\($0)\"" } ?? "null"
        return """
        {"number":\(number),"state":"\(state)","merged_at":\(merged),"title":"PR \(number)",
         "head":{"ref":"\(headRef)","sha":"\(headSha)"},"base":{"ref":"main","sha":"\(baseSha)"},
         "html_url":"https://github.com/octo/repo/pull/\(number)","updated_at":"2026-01-02T03:04:05Z"}
        """
    }

    private let reviewThreadsPage = """
    {"data":{"repository":{"pullRequest":{"reviewThreads":{
      "pageInfo":{"hasNextPage":false,"endCursor":null,"hasPreviousPage":false,"startCursor":null},
      "nodes":[
        {"id":"PRRT_open","isResolved":false,"isOutdated":false,
         "path":"Sources/A.swift","line":10,"originalLine":10,
         "comments":{"nodes":[
           {"databaseId":1001,"body":"first","createdAt":"2026-01-01T00:00:00Z",
            "author":{"login":"rev"},"path":"Sources/A.swift","line":10,"originalLine":10,"side":"RIGHT"},
           {"databaseId":1002,"body":"reply","createdAt":"2026-01-01T01:00:00Z",
            "author":{"login":"me"},"path":null,"line":null,"originalLine":null,"side":null}
         ]}},
        {"id":"PRRT_done","isResolved":true,"isOutdated":true,
         "path":"Sources/B.swift","line":null,"originalLine":20,
         "comments":{"nodes":[
           {"databaseId":1003,"body":"old","createdAt":"2026-01-02T00:00:00Z",
            "author":{"login":"rev"},"path":"Sources/B.swift","line":null,"originalLine":20,"side":"LEFT"}
         ]}}
      ]}}}}}
    """

    private let issueCommentsPage = """
    [{"id":5001,"node_id":"IC_abc","body":"general note","created_at":"2025-12-31T00:00:00Z",
      "html_url":"https://github.com/octo/repo/pull/7#issuecomment-5001","user":{"login":"someone"}}]
    """

    // MARK: - Reads

    func testCurrentUser() async throws {
        let stub = Stub(handler: router([
            ("GET /user", ok(#"{"id":42,"login":"laconicman","name":"Paul"}"#)),
        ]))
        let identity = try await connection(stub).currentUser()
        XCTAssertEqual(identity.id, 42)
        XCTAssertEqual(identity.username, "laconicman")
        XCTAssertEqual(identity.name, "Paul")

        let request = try XCTUnwrap(stub.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.host, "api.github.com")
        XCTAssertEqual(request.url?.path, "/user")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
    }

    func testMergeRequestsFiltersByHeadBranchAndMapsState() async throws {
        let stub = Stub(handler: router([
            ("GET /repos/octo/repo/pulls", ok("["
                + pullRequestJSON(number: 7, state: "open", headRef: "feat/x") + ","
                + pullRequestJSON(number: 8, state: "closed", mergedAt: "2026-01-01T00:00:00Z", headRef: "feat/x") + ","
                + pullRequestJSON(number: 9, state: "closed", headRef: "other") + ","
                + pullRequestJSON(number: 10, state: "closed", headRef: "feat/x") + "]")),
        ]))
        let summaries = try await connection(stub).mergeRequests(sourceBranch: "feat/x")
        XCTAssertEqual(summaries.map(\.iid), [7, 8, 10])
        XCTAssertEqual(summaries[0].state, .opened)
        XCTAssertEqual(summaries[1].state, .merged)
        XCTAssertEqual(summaries[2].state, .closed)
        XCTAssertEqual(summaries[0].sourceBranch, "feat/x")
        XCTAssertEqual(summaries[0].targetBranch, "main")
        XCTAssertEqual(summaries[0].webURL, "https://github.com/octo/repo/pull/7")
    }

    func testMergeRequestReturnsSummaryAndDiffRefs() async throws {
        let stub = Stub(handler: router([
            ("GET /repos/octo/repo/pulls/7", ok(pullRequestJSON(headSha: "H", baseSha: "B"))),
        ]))
        let (summary, diffRefs) = try await connection(stub).mergeRequest(iid: 7)
        XCTAssertEqual(summary.iid, 7)
        XCTAssertEqual(diffRefs.headSha, "H")
        XCTAssertEqual(diffRefs.baseSha, "B")
        XCTAssertNil(diffRefs.startSha)   // GitHub has no start-sha equivalent
    }

    func testMergeRequestDiffsMapsFilesEndpoint() async throws {
        let files = """
        [
          {"filename":"Sources/A.swift","previous_filename":null,"status":"modified",
           "patch":"@@ -1,2 +1,3 @@\\n ctx\\n+add\\n ctx2"},
          {"filename":"Sources/New.swift","previous_filename":null,"status":"added",
           "patch":"@@ -0,0 +1,1 @@\\n+new"},
          {"filename":"Sources/Renamed.swift","previous_filename":"Sources/Old.swift","status":"renamed",
           "patch":"@@ -1,1 +1,1 @@\\n-a\\n+b"},
          {"filename":"Assets/logo.png","previous_filename":null,"status":"modified"}
        ]
        """
        let stub = Stub(handler: router([
            ("GET /repos/octo/repo/pulls/7/files", ok(files)),
        ]))
        let diffs = try await connection(stub).mergeRequestDiffs(iid: 7)
        XCTAssertEqual(diffs.count, 4)
        XCTAssertEqual(diffs[0].oldPath, "Sources/A.swift")
        XCTAssertEqual(diffs[0].newPath, "Sources/A.swift")
        XCTAssertFalse(diffs[0].diff.isEmpty)
        XCTAssertFalse(diffs[0].newFile)
        XCTAssertFalse(diffs[0].deletedFile)
        XCTAssertFalse(diffs[0].tooLarge)
        XCTAssertTrue(diffs[1].newFile)
        XCTAssertEqual(diffs[2].oldPath, "Sources/Old.swift")   // previous_filename wins
        XCTAssertEqual(diffs[2].newPath, "Sources/Renamed.swift")
        XCTAssertTrue(diffs[3].tooLarge)                        // no patch → untrusted diff
        XCTAssertEqual(diffs[3].diff, "")
    }

    func testThreadsCombinesReviewThreadsAndIssueComments() async throws {
        let stub = Stub(handler: router([
            ("ReviewThreads", ok(reviewThreadsPage)),
            ("GET /repos/octo/repo/issues/7/comments", ok(issueCommentsPage)),
        ]))
        let threads = try await connection(stub).threads(iid: 7)
        XCTAssertEqual(threads.count, 3)
        // Merged sources sort by first-note time — the issue comment (2025-12-31)
        // precedes both review threads even though it arrives second.
        XCTAssertEqual(threads.map(\.id), ["IC_abc", "PRRT_open", "PRRT_done"])

        let open = try XCTUnwrap(threads.first { $0.id == "PRRT_open" })
        XCTAssertFalse(open.individualNote)
        XCTAssertTrue(open.resolvable)
        XCTAssertFalse(open.resolved)
        XCTAssertEqual(open.notes.count, 2)
        // Anchored comment: RIGHT side → .new.
        XCTAssertEqual(open.notes[0].position, Position(file: "Sources/A.swift", line: 10, lineType: .new))
        // Reply with null position fields inherits the thread anchor.
        XCTAssertEqual(open.notes[1].position, Position(file: "Sources/A.swift", line: 10, lineType: .new))
        XCTAssertEqual(open.notes[1].author, "me")

        let done = try XCTUnwrap(threads.first { $0.id == "PRRT_done" })
        XCTAssertTrue(done.resolved)
        // Outdated thread: line null → originalLine; LEFT side → .old.
        XCTAssertEqual(done.notes[0].position, Position(file: "Sources/B.swift", line: 20, lineType: .old))

        let comment = try XCTUnwrap(threads.first { $0.id == "IC_abc" })
        XCTAssertTrue(comment.individualNote)
        XCTAssertFalse(comment.resolvable)
        XCTAssertNil(comment.notes[0].position)
    }

    func testDiscussionsReducesThreads() async throws {
        let stub = Stub(handler: router([
            ("ReviewThreads", ok(reviewThreadsPage)),
            ("GET /repos/octo/repo/issues/7/comments", ok(issueCommentsPage)),
        ]))
        let summaries = try await connection(stub).discussions(iid: 7)
        XCTAssertEqual(summaries.count, 3)
        let open = try XCTUnwrap(summaries.first { $0.id == "PRRT_open" })
        XCTAssertEqual(open.noteCount, 2)
        XCTAssertTrue(open.onDiff)
        XCTAssertEqual(open.preview, "first")
        let comment = try XCTUnwrap(summaries.first { $0.id == "IC_abc" })
        XCTAssertFalse(comment.onDiff)
        XCTAssertFalse(comment.resolvable)
    }

    func testIssueCommentsPaginate() async throws {
        // Page 1 must be exactly full (100) to trigger page 2; page 2 ends the loop.
        func comment(_ n: Int) -> String {
            #"{"id":\#(n),"node_id":"IC_\#(n)","body":"b\#(n)","created_at":"2026-01-01T00:00:00Z","html_url":"u","user":{"login":"u"}}"#
        }
        let page1 = "[" + (1...100).map(comment).joined(separator: ",") + "]"
        let page2 = "[" + comment(101) + "]"
        let emptyThreads = #"{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null,"hasPreviousPage":false,"startCursor":null},"nodes":[]}}}}}"#
        let stub = Stub(handler: router([
            ("ReviewThreads", ok(emptyThreads)),
            ("comments?per_page=100&page=2", ok(page2)),
            ("comments?per_page=100&page=1", ok(page1)),
        ]))
        let threads = try await connection(stub).threads(iid: 7)
        XCTAssertEqual(threads.count, 101)
        XCTAssertEqual(stub.requests.count, 3)   // graphql + two REST pages
    }

    // MARK: - Writes: postDiscussion

    func testPostDiscussionGeneralPostsIssueComment() async throws {
        let created = """
        {"id":5001,"node_id":"IC_new","body":"finding","created_at":"2026-01-04T00:00:00Z",
         "html_url":"https://github.com/octo/repo/pull/7#issuecomment-5001","user":{"login":"me"}}
        """
        let stub = Stub(handler: router([
            ("POST /repos/octo/repo/issues/7/comments", ok(created)),
        ]))
        let posted = try await connection(stub).postDiscussion(
            iid: 7, body: "finding body", position: nil, diffRefs: nil
        )
        XCTAssertEqual(posted.discussionID, "IC_new")
        XCTAssertEqual(posted.noteID, 5001)
        XCTAssertEqual(posted.url, "https://github.com/octo/repo/pull/7#issuecomment-5001")

        let request = try XCTUnwrap(stub.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/repos/octo/repo/issues/7/comments")
        XCTAssertEqual(requestBody(request)["body"] as? String, "finding body")
    }

    func testPostDiscussionLineAnchorPostsReviewCommentThenResolvesThread() async throws {
        let reviewComment = #"{"id":2002,"node_id":"PRRC_x","html_url":"https://github.com/octo/repo/pull/7#discussion_r2002"}"#
        let threadLookup = """
        {"data":{"repository":{"pullRequest":{"reviewThreads":{
          "pageInfo":{"hasNextPage":false,"endCursor":null,"hasPreviousPage":false,"startCursor":null},
          "nodes":[{"id":"PRRT_new","comments":{"nodes":[{"databaseId":2002}]}}]
        }}}}}
        """
        let stub = Stub(handler: router([
            ("POST /repos/octo/repo/pulls/7/comments", ok(reviewComment)),
            ("ThreadCommentIDs", ok(threadLookup)),
        ]))
        let position = ResolvedPosition(newPath: "Sources/A.swift", newLine: 10)
        let refs = DiffRefs(baseSha: "B", headSha: "HEADSHA", startSha: nil)
        let posted = try await connection(stub).postDiscussion(
            iid: 7, body: "line finding", position: position, diffRefs: refs
        )
        XCTAssertEqual(posted.discussionID, "PRRT_new")
        XCTAssertEqual(posted.noteID, 2002)
        XCTAssertEqual(stub.requests.count, 2)

        let rest = stub.requests[0]
        XCTAssertEqual(rest.httpMethod, "POST")
        XCTAssertEqual(rest.url?.path, "/repos/octo/repo/pulls/7/comments")
        let body = requestBody(rest)
        XCTAssertEqual(body["body"] as? String, "line finding")
        XCTAssertEqual(body["commit_id"] as? String, "HEADSHA")
        XCTAssertEqual(body["path"] as? String, "Sources/A.swift")
        XCTAssertEqual(body["line"] as? Int, 10)
        XCTAssertEqual(body["side"] as? String, "RIGHT")

        // The GraphQL lookup ran against /graphql with owner/repo/number variables.
        let gql = stub.requests[1]
        XCTAssertEqual(gql.url?.path, "/graphql")
        let variables = requestBody(gql)["variables"] as? [String: Any]
        XCTAssertEqual(variables?["owner"] as? String, "octo")
        XCTAssertEqual(variables?["repo"] as? String, "repo")
        XCTAssertEqual(variables?["number"] as? Int, 7)
    }

    func testPostDiscussionLineAnchorWithoutHeadSHAThrows() async throws {
        let stub = Stub(handler: router([]))
        let position = ResolvedPosition(newPath: "a.swift", newLine: 1)
        do {
            _ = try await connection(stub).postDiscussion(
                iid: 7, body: "x", position: position, diffRefs: DiffRefs(baseSha: nil, headSha: nil, startSha: nil)
            )
            XCTFail("expected missingHeadSHA")
        } catch let error as GitHubRequestError {
            XCTAssertEqual(error, .missingHeadSHA)
        }
        XCTAssertTrue(stub.requests.isEmpty)
    }

    // MARK: - Writes: postNote / resolveThread / updateNote

    func testPostNoteRepliesViaGraphQLMutation() async throws {
        let response = """
        {"data":{"addPullRequestReviewThreadReply":{"comment":{"databaseId":3003,"url":"https://github.com/octo/repo/pull/7#discussion_r3003"}}}}
        """
        let stub = Stub(handler: router([
            ("ReplyToReviewThread", ok(response)),
        ]))
        let posted = try await connection(stub).postNote(
            iid: 7, discussionID: "PRRT_x", body: "a reply"
        )
        XCTAssertEqual(posted.discussionID, "PRRT_x")
        XCTAssertEqual(posted.noteID, 3003)
        XCTAssertEqual(posted.url, "https://github.com/octo/repo/pull/7#discussion_r3003")

        let request = try XCTUnwrap(stub.requests.first)
        XCTAssertEqual(request.url?.path, "/graphql")
        let body = requestBody(request)
        let variables = try XCTUnwrap(body["variables"] as? [String: Any])
        XCTAssertEqual(variables["threadId"] as? String, "PRRT_x")
        XCTAssertEqual(variables["body"] as? String, "a reply")
    }

    func testPostNoteRejectsNonThreadID() async throws {
        let stub = Stub(handler: router([]))
        do {
            _ = try await connection(stub).postNote(iid: 7, discussionID: "IC_abc", body: "x")
            XCTFail("expected unsupportedOperation")
        } catch let error as GitHubRequestError {
            guard case .unsupportedOperation = error else {
                return XCTFail("wrong error: \(error)")
            }
        }
        XCTAssertTrue(stub.requests.isEmpty)
    }

    func testResolveThreadUsesGraphQLMutation() async throws {
        let stub = Stub(handler: router([
            ("ResolveReviewThread", ok(#"{"data":{"resolveReviewThread":{"thread":{"id":"PRRT_x","isResolved":true}}}}"#)),
            ("UnresolveReviewThread", ok(#"{"data":{"unresolveReviewThread":{"thread":{"id":"PRRT_x","isResolved":false}}}}"#)),
        ]))
        try await connection(stub).resolveThread(iid: 7, discussionID: "PRRT_x", resolved: true)
        try await connection(stub).resolveThread(iid: 7, discussionID: "PRRT_x", resolved: false)
        XCTAssertEqual(stub.requests.count, 2)
        let firstVars = requestBody(stub.requests[0])["variables"] as? [String: Any]
        XCTAssertEqual(firstVars?["threadId"] as? String, "PRRT_x")
    }

    func testResolveThreadRejectsIssueComment() async throws {
        let stub = Stub(handler: router([]))
        do {
            try await connection(stub).resolveThread(iid: 7, discussionID: "IC_abc", resolved: true)
            XCTFail("expected unsupportedOperation")
        } catch is GitHubRequestError {
            // expected
        }
        XCTAssertTrue(stub.requests.isEmpty)
    }

    func testUpdateNoteRoutesByIDKind() async throws {
        let reviewComment = #"{"id":2002,"node_id":"PRRC_x","html_url":"u"}"#
        let issueComment = #"{"id":5001,"node_id":"IC_x","body":"b","created_at":"c","html_url":"u","user":{"login":"u"}}"#
        let stub = Stub(handler: router([
            ("PATCH /repos/octo/repo/pulls/comments/2002", ok(reviewComment)),
            ("PATCH /repos/octo/repo/issues/comments/5001", ok(issueComment)),
        ]))
        try await connection(stub).updateNote(iid: 7, discussionID: "PRRT_x", noteID: 2002, body: "edited")
        try await connection(stub).updateNote(iid: 7, discussionID: "IC_abc", noteID: 5001, body: "edited")
        XCTAssertEqual(stub.requests.map { $0.url?.path }, [
            "/repos/octo/repo/pulls/comments/2002",
            "/repos/octo/repo/issues/comments/5001",
        ])
        XCTAssertEqual(stub.requests.map(\.httpMethod), ["PATCH", "PATCH"])
        XCTAssertEqual(requestBody(stub.requests[0])["body"] as? String, "edited")
    }

    // MARK: - Policy

    func testShouldFallbackToGeneralNoteNeeds422OnInferredAnchor() {
        let connection = connection(Stub(handler: { _ in (Data(), 200) }))
        let inferred = ResolvedPosition(
            oldPath: "a.swift", newPath: "a.swift", oldLine: 5, newLine: 5, outsideHunks: true
        )
        let observed = ResolvedPosition(newPath: "a.swift", newLine: 11)
        XCTAssertTrue(connection.shouldFallbackToGeneralNote(
            error: GitHubRequestError.httpStatus(422, "Validation Failed"), anchor: inferred))
        XCTAssertFalse(connection.shouldFallbackToGeneralNote(
            error: GitHubRequestError.httpStatus(422, nil), anchor: observed))  // in-diff: real bug
        XCTAssertFalse(connection.shouldFallbackToGeneralNote(
            error: GitHubRequestError.httpStatus(422, nil), anchor: nil))
        XCTAssertFalse(connection.shouldFallbackToGeneralNote(
            error: GitHubRequestError.httpStatus(500, nil), anchor: inferred)) // ambiguous
        XCTAssertFalse(connection.shouldFallbackToGeneralNote(
            error: URLError(.timedOut), anchor: inferred))                     // transport
        XCTAssertFalse(connection.shouldFallbackToGeneralNote(
            error: GitHubRequestError.graphql("boom"), anchor: inferred))
    }

    func testNoteURLPrefersPostedPermalink() {
        let connection = connection(Stub(handler: { _ in (Data(), 200) }))
        let posted = PostedDiscussion(discussionID: "PRRT_x", noteID: 1, url: "https://example.com/n1")
        XCTAssertEqual(connection.noteURL(for: posted, mergeRequestWebURL: "https://example.com/mr"),
                       "https://example.com/n1")
        let bare = PostedDiscussion(discussionID: "PRRT_x", noteID: 1)
        XCTAssertNil(connection.noteURL(for: bare, mergeRequestWebURL: "https://example.com/mr"))
    }

    // MARK: - Mapping (pure)

    func testAnchorPrefersNewSideThenOldSide() throws {
        let both = ResolvedPosition(
            oldPath: "old.swift", newPath: "new.swift", oldLine: 3, newLine: 7
        )
        var anchor = try GitHubConnection.anchor(both)
        XCTAssertEqual(anchor.path, "new.swift")
        XCTAssertEqual(anchor.line, 7)
        XCTAssertEqual(anchor.side, "RIGHT")
        anchor = try GitHubConnection.anchor(ResolvedPosition(oldPath: "old.swift", oldLine: 3))
        XCTAssertEqual(anchor.path, "old.swift")
        XCTAssertEqual(anchor.line, 3)
        XCTAssertEqual(anchor.side, "LEFT")
        XCTAssertThrowsError(try GitHubConnection.anchor(ResolvedPosition()))
    }

    func testIsReviewThreadChecksNodeIDPrefix() {
        XCTAssertTrue(GitHubConnection.isReviewThread("PRRT_abc123"))
        XCTAssertFalse(GitHubConnection.isReviewThread("IC_abc123"))
        XCTAssertFalse(GitHubConnection.isReviewThread("12345"))   // bare numeric id isn't ours
    }

    func testPullRequestStateMapping() {
        func pr(_ state: String, mergedAt: String?) -> GHPullRequest {
            GHPullRequest(number: 1, state: state, merged_at: mergedAt, title: "t",
                          head: .init(ref: "b", sha: "h"), base: .init(ref: "m", sha: "s"),
                          html_url: "u", updated_at: "2026-01-01T00:00:00Z")
        }
        XCTAssertEqual(GitHubConnection.summary(pr("open", mergedAt: nil)).state, .opened)
        XCTAssertEqual(GitHubConnection.summary(pr("closed", mergedAt: "2026-01-01T00:00:00Z")).state, .merged)
        XCTAssertEqual(GitHubConnection.summary(pr("closed", mergedAt: nil)).state, .closed)
    }
}
