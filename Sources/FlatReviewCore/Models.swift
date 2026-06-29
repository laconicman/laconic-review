import Foundation

/// The token's identity (`GET /user`).
public struct Identity: Equatable, Sendable, Codable {
    /// GitLab types user/project `id` as `integer, format: int64`, so we mirror that wire type
    /// rather than narrowing to `Int` at the seam. (`iid` is a plain `integer` upstream — `Int`.)
    public let id: Int64
    public let username: String
    public let name: String?
}

/// MR lifecycle state, mirroring GitLab's `state` field.
public enum MergeRequestState: String, Sendable, Codable, Equatable {
    case opened, closed, merged, locked, unknown
}

/// A merge request reduced to what review resolution needs — provider-neutral.
public struct MergeRequestSummary: Equatable, Sendable, Codable {
    public let iid: Int
    public let state: MergeRequestState
    public let title: String
    public let sourceBranch: String
    public let targetBranch: String
    public let webURL: String?
    public let updatedAt: Date?

    public init(
        iid: Int, state: MergeRequestState, title: String,
        sourceBranch: String, targetBranch: String, webURL: String?, updatedAt: Date?
    ) {
        self.iid = iid; self.state = state; self.title = title
        self.sourceBranch = sourceBranch; self.targetBranch = targetBranch
        self.webURL = webURL; self.updatedAt = updatedAt
    }
}

/// The three SHAs GitLab uses to anchor a line comment. This is the server-side source of
/// truth for `position`; the markdown report never persists these — it fetches them fresh.
public struct DiffRefs: Equatable, Sendable, Codable {
    public let baseSha: String?
    public let headSha: String?
    public let startSha: String?
}

/// A review thread reduced to its publish-relevant shape (system-only threads are dropped
/// upstream of this type). `onDiff` distinguishes a line-anchored thread from a general one.
public struct DiscussionSummary: Equatable, Sendable, Codable {
    public let id: String
    public let noteCount: Int
    public let resolvable: Bool
    public let resolved: Bool
    public let onDiff: Bool
    public let preview: String?
}
