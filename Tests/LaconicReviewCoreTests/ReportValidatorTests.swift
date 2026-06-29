import Testing
@testable import LaconicReviewCore

@Suite("ReportValidator")
struct ReportValidatorTests {
    private func report(_ findings: [Finding]) -> ReviewReport {
        ReviewReport(
            header: ReviewHeader(branch: "b", base: "develop", iid: 1, iteration: 1, skill: ""),
            findings: findings
        )
    }

    @Test("a well-formed report has no diagnostics")
    func clean() {
        let c1 = Finding(
            id: "C1", severity: "concern", status: "open", scope: .line,
            file: "A.swift", lineStart: 10, lineEnd: 12, lineType: .new, links: [],
            markdown: "### C1. Title\nbody"
        )
        #expect(ReportValidator.validate(report([c1])).isEmpty)
    }

    @Test("flags missing file/line, unknown vocab, dangling links; warns on a leaked ##")
    func catchesProblems() {
        let bad = Finding(
            id: "C1", severity: "huge", status: "todo", scope: .line,
            file: nil, lineStart: nil, lineEnd: nil, lineType: .new, links: ["Z9"],
            markdown: "### C1\n## Leaked section\nbody"
        )
        let diagnostics = ReportValidator.validate(report([bad]))
        let messages = diagnostics.map(\.message).joined(separator: "\n")

        #expect(messages.contains("severity"))                 // huge ∉ vocab
        #expect(messages.contains("status"))                   // todo ∉ vocab
        #expect(messages.contains("scope=line requires"))      // no file/line
        #expect(messages.contains("unknown finding `Z9`"))     // dangling link
        #expect(diagnostics.contains { $0.level == .warning && $0.message.contains("##") })
        #expect(diagnostics.contains { $0.level == .error })
    }

    @Test("a level-3 heading is not mistaken for a leaked section")
    func headingLevelsDistinguished() {
        let c1 = Finding(
            id: "C1", severity: "nit", status: "closed", scope: .general,
            file: nil, lineStart: nil, lineEnd: nil, lineType: .new, links: [],
            markdown: "### C1. Fine\nNo level-2 heading here."
        )
        #expect(ReportValidator.validate(report([c1])).isEmpty)
    }
}
