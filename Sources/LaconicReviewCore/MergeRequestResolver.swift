import Foundation

/// The outcome of resolving a branch to a merge request.
public enum MergeRequestResolution: Sendable, Equatable {
    /// Exactly one open MR — use it silently.
    case resolved(iid: Int)
    /// No MR for this branch — a pre-MR (local) review.
    case none
    /// The caller must choose: branch is the base, several open MRs, or only closed/merged.
    case ambiguous(reason: AmbiguityReason, candidates: [MergeRequestSummary])
}

public enum AmbiguityReason: String, Sendable, Equatable, Encodable {
    case branchIsBase
    case multipleOpen
    case onlyClosedOrMerged
}

/// Decides which merge request a branch maps to, given the MRs GitLab reports for it.
///
/// Pure and synchronous — it never talks to the network, so the decision tree is unit-tested
/// in isolation. Mirrors the skill's MR-resolution UX: one open MR is used silently; anything
/// ambiguous returns up to five open candidates (most-recently-updated first) for the caller
/// to confirm.
public enum MergeRequestResolver {
    public static func resolve(
        branch: String,
        base: String,
        mergeRequests: [MergeRequestSummary]
    ) -> MergeRequestResolution {
        guard branch != base else {
            return .ambiguous(reason: .branchIsBase, candidates: topOpen(mergeRequests))
        }
        let open = mergeRequests.filter { $0.state == .opened }
        switch open.count {
        case 1:
            return .resolved(iid: open[0].iid)
        case 0:
            return mergeRequests.isEmpty
                ? .none
                : .ambiguous(reason: .onlyClosedOrMerged, candidates: topOpen(mergeRequests))
        default:
            return .ambiguous(reason: .multipleOpen, candidates: topOpen(open))
        }
    }

    /// Up to five open MRs, most-recently-updated first.
    static func topOpen(_ mrs: [MergeRequestSummary]) -> [MergeRequestSummary] {
        Array(
            mrs.filter { $0.state == .opened }
               .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
               .prefix(5)
        )
    }
}

extension MergeRequestResolution: Encodable {
    enum CodingKeys: String, CodingKey { case kind, iid, reason, candidates }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .resolved(let iid):
            try container.encode("resolved", forKey: .kind)
            try container.encode(iid, forKey: .iid)
        case .none:
            try container.encode("none", forKey: .kind)
        case .ambiguous(let reason, let candidates):
            try container.encode("ambiguous", forKey: .kind)
            try container.encode(reason, forKey: .reason)
            try container.encode(candidates, forKey: .candidates)
        }
    }
}
