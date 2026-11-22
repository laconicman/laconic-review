import Foundation
import GitLabConnection
import LaconicReviewCore
import XCTest

/// GitLab-specific seams that moved out of `LaconicReviewCore` with `GitLabConnection`.
final class GitLabConnectionTests: XCTestCase {

    func testFallbackToGeneralNoteNeedsDefinite400OnInferredAnchor() {
        // Only a definite position rejection of an *inferred* anchor may retry
        // as a general note — anything else risks double-posting.
        let inferred = ResolvedPosition(
            oldPath: "a.swift", newPath: "a.swift", oldLine: 5, newLine: 5, outsideHunks: true
        )
        let observed = ResolvedPosition(newPath: "a.swift", newLine: 11)
        XCTAssertTrue(DiscussionPostError.shouldFallbackToGeneralNote(
            error: DiscussionPostError.httpStatus(400), anchor: inferred))
        XCTAssertFalse(DiscussionPostError.shouldFallbackToGeneralNote(
            error: DiscussionPostError.httpStatus(400), anchor: observed))   // in-diff: real bug, don't mask
        XCTAssertFalse(DiscussionPostError.shouldFallbackToGeneralNote(
            error: DiscussionPostError.httpStatus(400), anchor: nil))
        XCTAssertFalse(DiscussionPostError.shouldFallbackToGeneralNote(
            error: DiscussionPostError.httpStatus(500), anchor: inferred))  // ambiguous — may have committed
        XCTAssertFalse(DiscussionPostError.shouldFallbackToGeneralNote(
            error: URLError(.timedOut), anchor: inferred))                  // transport — may have committed
    }
}
