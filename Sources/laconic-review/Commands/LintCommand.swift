import ArgumentParser
import Foundation
import LaconicReviewCore

/// Validate a review report against the format — offline, no token or network.
///
/// Exits non-zero when there are errors, so the review skill can run it as its final
/// self-heal step and retry on failure.
struct LintCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lint",
        abstract: "Validate a review report against the format (offline; no token/network)."
    )

    @Argument(help: "Path to the review report markdown.")
    var report: String

    @Flag(help: "Emit machine-readable JSON.")
    var json = false

    func run() throws {
        let url = URL(fileURLWithPath: report)
        let parsed: ReviewReport
        do {
            parsed = try ReportParser.parse(try String(contentsOf: url, encoding: .utf8))
        } catch {
            let diagnostic = ReportDiagnostic(level: .error, message: "\(error)")
            print(json ? (try? JSON.string([diagnostic])) ?? "\(error)" : "error: \(error)")
            throw ExitCode.failure
        }

        let diagnostics = ReportValidator.validate(parsed)
        let errorCount = diagnostics.filter { $0.level == .error }.count

        if json {
            print(try JSON.string(diagnostics))
        } else if diagnostics.isEmpty {
            print("✓ \(parsed.findings.count) finding(s), no issues.")
        } else {
            for d in diagnostics {
                print("\(d.level.rawValue): \(d.findingID.map { "\($0): " } ?? "")\(d.message)")
            }
            print("\(parsed.findings.count) finding(s), \(errorCount) error(s), \(diagnostics.count - errorCount) warning(s).")
        }

        if errorCount > 0 { throw ExitCode.failure }
    }
}
