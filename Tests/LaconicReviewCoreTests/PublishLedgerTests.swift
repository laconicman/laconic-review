import Foundation
import Testing
@testable import LaconicReviewCore

@Suite("PublishLedger")
struct PublishLedgerTests {
    @Test("loading a nonexistent ledger yields an empty one")
    func emptyWhenMissing() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).published.json")
        #expect(try PublishLedger.load(from: url).threads.isEmpty)
    }

    @Test("record → save → reload round-trips")
    func roundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-\(UUID().uuidString).published.json")
        defer { try? FileManager.default.removeItem(at: url) }

        var ledger = PublishLedger()
        ledger.record("C1", PublishedThread(discussionID: "abc123", noteID: 42, url: "https://lab/mr#note_42"))
        #expect(ledger.published("C1"))
        #expect(!ledger.published("C2"))

        try ledger.save(to: url)
        let reloaded = try PublishLedger.load(from: url)
        #expect(reloaded == ledger)
        #expect(reloaded.thread(for: "C1")?.discussionID == "abc123")
        #expect(reloaded.url(for: "C1") == "https://lab/mr#note_42")
    }

    @Test("report URL maps to its sibling .published.json")
    func siblingURL() {
        let report = URL(fileURLWithPath: "/repo/.claude/reviews/fix-x/2.md")
        #expect(PublishLedger.url(forReport: report).lastPathComponent == "2.published.json")
    }
}
