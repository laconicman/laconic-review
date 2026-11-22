import Foundation
import LaconicReviewCore

/// Renders any `Encodable` as stable, pretty JSON for `--json` output.
enum JSON {
    static func string<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

/// `MR !965` on GitLab, `PR #965` on GitHub — the forge-appropriate way to name a review target.
func refLabel(_ kind: ReviewHostKind, _ iid: Int) -> String {
    kind == .github ? "PR #\(iid)" : "MR !\(iid)"
}
