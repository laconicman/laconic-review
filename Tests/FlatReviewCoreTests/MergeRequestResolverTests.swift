import Testing
import Foundation
@testable import FlatReviewCore

/// The MR-resolution decision tree is pure, so it is tested without any network.
@Suite struct MergeRequestResolverTests {
    private func mr(_ iid: Int, _ state: MergeRequestState, updated: TimeInterval = 0) -> MergeRequestSummary {
        MergeRequestSummary(
            iid: iid, state: state, title: "MR \(iid)",
            sourceBranch: "feature/x", targetBranch: "develop",
            webURL: nil, updatedAt: Date(timeIntervalSince1970: updated)
        )
    }

    @Test func singleOpenResolvesSilently() {
        let result = MergeRequestResolver.resolve(branch: "feature/x", base: "develop", mergeRequests: [mr(965, .opened)])
        #expect(result == .resolved(iid: 965))
    }

    @Test func noMergeRequestsMeansPreMR() {
        let result = MergeRequestResolver.resolve(branch: "feature/x", base: "develop", mergeRequests: [])
        #expect(result == .none)
    }

    @Test func onlyMergedOrClosedIsAmbiguous() {
        let result = MergeRequestResolver.resolve(branch: "feature/x", base: "develop", mergeRequests: [mr(900, .merged)])
        #expect(result == .ambiguous(reason: .onlyClosedOrMerged, candidates: []))
    }

    @Test func branchEqualToBaseIsAmbiguous() {
        let result = MergeRequestResolver.resolve(branch: "develop", base: "develop", mergeRequests: [])
        #expect(result == .ambiguous(reason: .branchIsBase, candidates: []))
    }

    @Test func multipleOpenReturnsCandidatesNewestFirst() {
        let result = MergeRequestResolver.resolve(
            branch: "feature/x", base: "develop",
            mergeRequests: [mr(1, .opened, updated: 100), mr(2, .opened, updated: 200)]
        )
        guard case let .ambiguous(reason, candidates) = result else {
            Issue.record("expected .ambiguous, got \(result)")
            return
        }
        #expect(reason == .multipleOpen)
        #expect(candidates.map(\.iid) == [2, 1])
    }
}
