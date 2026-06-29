import Foundation

/// Parses the markdown SSOT into a ``ReviewReport``.
///
/// Format (see the README → *Report format*): one `<!-- review … -->` anchor, then one
/// `<!-- finding … -->` anchor per finding, each immediately followed by that finding's
/// verbatim prose (heading + body) up to the next anchor. Anchor attributes are
/// space-separated `key=value` pairs whose values contain no spaces.
public enum ReportParser {

    public enum ParseError: Error, CustomStringConvertible, Equatable {
        case missingReviewHeader
        case malformedReviewHeader(missing: String)

        public var description: String {
            switch self {
            case .missingReviewHeader:
                return "No `<!-- review … -->` anchor found — is this a laconic-review report?"
            case .malformedReviewHeader(let missing):
                return "The `<!-- review … -->` anchor is missing required key `\(missing)`."
            }
        }
    }

    public static func parse(_ markdown: String) throws -> ReviewReport {
        // Local (not a static let): Regex isn't Sendable, so a stored global trips Swift 6.
        let anchor = /<!--\s+(review|finding)\s+(.*?)\s*-->/
        let matches = Array(markdown.matches(of: anchor))

        guard let review = matches.first(where: { $0.output.1 == "review" }) else {
            throw ParseError.missingReviewHeader
        }
        let header = try header(from: attributes(String(review.output.2)))

        var findings: [Finding] = []
        for (i, match) in matches.enumerated() where match.output.1 == "finding" {
            let proseStart = match.range.upperBound
            let proseEnd = i + 1 < matches.count ? matches[i + 1].range.lowerBound : markdown.endIndex
            let prose = markdown[proseStart..<proseEnd].trimmingCharacters(in: .whitespacesAndNewlines)
            findings.append(finding(from: attributes(String(match.output.2)), markdown: prose))
        }
        return ReviewReport(header: header, findings: findings)
    }

    // MARK: - Helpers

    /// Splits `key=value key=value` (values are space-free) into a dictionary.
    private static func attributes(_ string: String) -> [String: String] {
        var result: [String: String] = [:]
        for token in string.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
            guard let eq = token.firstIndex(of: "=") else { continue }
            result[String(token[..<eq])] = String(token[token.index(after: eq)...])
        }
        return result
    }

    private static func header(from a: [String: String]) throws -> ReviewHeader {
        func required(_ key: String) throws -> String {
            guard let value = a[key] else { throw ParseError.malformedReviewHeader(missing: key) }
            return value
        }
        return ReviewHeader(
            branch: try required("branch"),
            base: try required("base"),
            iid: Int(try required("iid")) ?? 0,
            iteration: a["iteration"].flatMap(Int.init) ?? 1,
            skill: a["skill"] ?? ""
        )
    }

    private static func finding(from a: [String: String], markdown: String) -> Finding {
        let (start, end) = lineRange(a["line"])
        return Finding(
            id: a["id"] ?? "",
            severity: a["severity"] ?? "",
            status: a["status"] ?? "open",
            scope: FindingScope(rawValue: a["scope"] ?? "general") ?? .general,
            file: a["file"],
            lineStart: start,
            lineEnd: end,
            lineType: LineSide(rawValue: a["line_type"] ?? "new") ?? .new,
            links: a["links"].map { $0.split(separator: ",").map(String.init) } ?? [],
            markdown: markdown
        )
    }

    /// Parses `"18-22"` → (18, 22), `"18"` → (18, nil), missing/invalid → (nil, nil).
    private static func lineRange(_ string: String?) -> (Int?, Int?) {
        guard let string else { return (nil, nil) }
        let parts = string.split(separator: "-", maxSplits: 1).map { Int($0) }
        switch parts.count {
        case 2: return (parts[0], parts[1])
        case 1: return (parts[0], nil)
        default: return (nil, nil)
        }
    }
}
