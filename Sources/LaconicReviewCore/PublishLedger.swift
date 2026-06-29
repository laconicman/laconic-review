import Foundation

/// A published-thread record — enough to cross-link findings and to resolve the thread later.
public struct PublishedThread: Equatable, Sendable, Codable {
    public let discussionID: String
    public let noteID: Int?
    public let url: String?

    public init(discussionID: String, noteID: Int?, url: String?) {
        self.discussionID = discussionID
        self.noteID = noteID
        self.url = url
    }

    enum CodingKeys: String, CodingKey {
        case discussionID = "discussion_id"
        case noteID = "note_id"
        case url
    }
}

/// Idempotency ledger for `publish`: maps finding id → the thread it created, persisted next to
/// the report as `<N>.published.json`. Re-running `publish` skips findings already recorded, so
/// publishing is safe across review iterations.
public struct PublishLedger: Equatable, Sendable {
    public private(set) var threads: [String: PublishedThread]

    public init(threads: [String: PublishedThread] = [:]) { self.threads = threads }

    public func published(_ findingID: String) -> Bool { threads[findingID] != nil }
    public func thread(for findingID: String) -> PublishedThread? { threads[findingID] }
    public func url(for findingID: String) -> String? { threads[findingID]?.url }
    public mutating func record(_ findingID: String, _ thread: PublishedThread) {
        threads[findingID] = thread
    }

    /// Loads the ledger at `url`, or an empty one if the file doesn't exist yet.
    public static func load(from url: URL) throws -> PublishLedger {
        guard FileManager.default.fileExists(atPath: url.path) else { return PublishLedger() }
        let threads = try JSONDecoder().decode([String: PublishedThread].self, from: Data(contentsOf: url))
        return PublishLedger(threads: threads)
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(threads).write(to: url, options: .atomic)
    }

    /// The `<N>.published.json` sibling of a report at `<N>.md`.
    public static func url(forReport report: URL) -> URL {
        report.deletingPathExtension().appendingPathExtension("published.json")
    }
}
