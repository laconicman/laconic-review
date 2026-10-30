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

/// A neutral diff anchor for a discussion: a file, and a line on one side of the diff —
/// or just the file for file-level comments (`line == nil`, `lineType == .file`). The seam
/// combines this with ``DiffRefs`` (fetched at publish) to build GitLab's `position` object.
public struct Position: Equatable, Sendable, Codable {
    public let file: String
    public let line: Int?
    public let lineType: LineSide

    public init(file: String, line: Int?, lineType: LineSide) {
        self.file = file
        self.line = line
        self.lineType = lineType
    }
}

/// The result of creating a discussion: the thread id (to resolve later) and its first note id
/// (to anchor a `#note_<id>` URL). Provider-neutral — the publish layer composes the URL.
public struct PostedDiscussion: Equatable, Sendable {
    public let discussionID: String
    public let noteID: Int?

    public init(discussionID: String, noteID: Int?) {
        self.discussionID = discussionID
        self.noteID = noteID
    }
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

/// One note inside a review thread — everything `fetch` needs to hand an agent.
public struct ThreadNote: Equatable, Sendable, Codable {
    public let id: Int64
    /// Display name ("Иван Лавров") and handle ("s.lavrov") of the author.
    public let author: String
    public let username: String
    public let createdAt: Date?
    /// The note body, verbatim markdown.
    public let body: String
    /// A diff anchor when the thread sits on a line (`nil` for general threads).
    public let position: Position?

    public init(id: Int64, author: String, username: String, createdAt: Date?, body: String, position: Position?) {
        self.id = id
        self.author = author
        self.username = username
        self.createdAt = createdAt
        self.body = body
        self.position = position
    }
}

/// A review thread with full note bodies — the unit `fetch` delivers.
/// System notes are dropped at mapping time; threads that held only system notes are dropped too.
public struct DiscussionThread: Equatable, Sendable, Codable {
    public let id: String
    /// GitLab's `individual_note`: a standalone comment, not a resolvable thread.
    public let individualNote: Bool
    public let resolvable: Bool
    public let resolved: Bool
    public let notes: [ThreadNote]

    public init(id: String, individualNote: Bool, resolvable: Bool, resolved: Bool, notes: [ThreadNote]) {
        self.id = id
        self.individualNote = individualNote
        self.resolvable = resolvable
        self.resolved = resolved
        self.notes = notes
    }

    /// The thread's diff anchor — GitLab puts the same position on each note of the thread.
    public var position: Position? { notes.lazy.compactMap(\.position).first }

    /// Open business for the merge author: a resolvable thread nobody resolved yet.
    public var isOpen: Bool { resolvable && !resolved }
}

/// What `fetch` returns: the MR plus every non-system thread, verbatim.
public struct Inbox: Equatable, Sendable, Codable {
    public let iid: Int
    public let title: String
    public let webURL: String?
    public let branch: String
    public let fetchedAt: Date
    public let threads: [DiscussionThread]

    public init(iid: Int, title: String, webURL: String?, branch: String, fetchedAt: Date, threads: [DiscussionThread]) {
        self.iid = iid
        self.title = title
        self.webURL = webURL
        self.branch = branch
        self.fetchedAt = fetchedAt
        self.threads = threads
    }

    public var openCount: Int { threads.filter(\.isOpen).count }
    public var resolvedCount: Int { threads.filter(\.resolved).count }
}
