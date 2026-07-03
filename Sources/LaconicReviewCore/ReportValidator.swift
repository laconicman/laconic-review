import Foundation

/// A lint diagnostic about a report, surfaced by ``ReportValidator``.
public struct ReportDiagnostic: Equatable, Sendable, Codable {
    public enum Level: String, Sendable, Codable { case error, warning }
    public let level: Level
    /// The finding the diagnostic concerns, or `nil` for a report-level one.
    public let findingID: String?
    public let message: String

    public init(level: Level, findingID: String? = nil, message: String) {
        self.level = level
        self.findingID = findingID
        self.message = message
    }
}

/// Validates a parsed ``ReviewReport`` against the locked format (see `Docs/report-format.md`).
///
/// Pure and offline — the explicit primitive behind `laconic-review lint`, and the skill's
/// final self-heal check. Header presence (the review anchor and `branch`/`base`/`iid`) is
/// enforced by ``ReportParser`` at parse time, which throws *before* this runs; everything here
/// is a per-finding check the parser tolerates but a well-formed report must satisfy.
public enum ReportValidator {
    static let severities: Set<String> = ["blocker", "concern", "nit"]
    static let statuses: Set<String> = ["open", "in_progress", "closed", "needs_info"]
    static let severityByPrefix: [Character: String] = ["B": "blocker", "C": "concern", "N": "nit"]

    public static func validate(_ report: ReviewReport) -> [ReportDiagnostic] {
        var diagnostics: [ReportDiagnostic] = []
        let declaredIDs = Set(report.findings.map(\.id))

        for finding in report.findings {
            let id = finding.id.isEmpty ? nil : finding.id

            if finding.id.isEmpty {
                diagnostics.append(.init(level: .error, message: "a finding is missing `id`"))
            }
            if !severities.contains(finding.severity) {
                diagnostics.append(.init(level: .error, findingID: id,
                    message: "unknown/missing severity `\(finding.severity)` (expected \(Self.list(severities)))"))
            }
            if !statuses.contains(finding.status) {
                diagnostics.append(.init(level: .error, findingID: id,
                    message: "unknown status `\(finding.status)` (expected \(Self.list(statuses)))"))
            }
            if finding.scope == .line, finding.file == nil || finding.lineStart == nil {
                diagnostics.append(.init(level: .error, findingID: id,
                    message: "scope=line requires `file` and `line` (else it silently degrades to a general note)"))
            }
            for link in finding.links where !declaredIDs.contains(link) {
                diagnostics.append(.init(level: .error, findingID: id,
                    message: "links to unknown finding `\(link)`"))
            }
            // The id prefix is a birth mnemonic (B/C/N); `severity=` is authoritative. A mismatch
            // is legal for a carried-forward finding whose severity was later revised (the id is
            // frozen), but on a newborn it means the id or the severity is wrong — warn, human decides.
            if let prefix = finding.id.first, let expected = severityByPrefix[prefix],
               severities.contains(finding.severity), finding.severity != expected {
                diagnostics.append(.init(level: .warning, findingID: id,
                    message: "id prefix `\(prefix)` says \(expected), but severity=\(finding.severity) — if this finding is new, renumber it (ids freeze at publish)"))
            }
            // Back-to-back invariant: a `##` heading inside a finding's prose publishes into the
            // comment body — almost always a leaked section header. Warn, don't fail.
            if finding.markdown.contains(/(?m)^[ \t]*##[ \t]/) {
                diagnostics.append(.init(level: .warning, findingID: id,
                    message: "prose contains a `##` heading — it will publish into the comment body; group in the front-matter instead"))
            }
        }
        return diagnostics
    }

    private static func list(_ set: Set<String>) -> String { set.sorted().joined(separator: " | ") }
}
