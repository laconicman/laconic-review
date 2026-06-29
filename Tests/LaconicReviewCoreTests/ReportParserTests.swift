import Testing
@testable import LaconicReviewCore

@Suite("ReportParser")
struct ReportParserTests {
    let sample = """
    <!-- review branch=fix/logout base=develop iid=965 iteration=2 skill=laconic-review@1 -->
    # Review for fix/logout

    <!-- finding id=C1 severity=concern status=open scope=line file=Sources/Auth.swift line=18-22 line_type=new links=C3 -->
    ### 🟡 C1. Token not cleared — ⏳ Open
    The session token survives logout.

    ```swift
    session.clear()
    ```

    <!-- finding id=G1 severity=nit status=resolved scope=general -->
    ### 🔵 G1. Naming
    A general comment.
    """

    @Test("parses the review header")
    func header() throws {
        let report = try ReportParser.parse(sample)
        #expect(report.header.branch == "fix/logout")
        #expect(report.header.base == "develop")
        #expect(report.header.iid == 965)
        #expect(report.header.iteration == 2)
        #expect(report.header.skill == "laconic-review@1")
    }

    @Test("parses a line finding with its position and verbatim prose")
    func lineFinding() throws {
        let c1 = try #require(try ReportParser.parse(sample).findings.first { $0.id == "C1" })
        #expect(c1.scope == .line)
        #expect(c1.file == "Sources/Auth.swift")
        #expect(c1.lineStart == 18)
        #expect(c1.lineEnd == 22)
        #expect(c1.lineType == .new)
        #expect(c1.links == ["C3"])
        #expect(c1.isOpen)
        #expect(c1.markdown.contains("survives logout"))
        #expect(c1.markdown.contains("session.clear()"))      // code fence preserved verbatim
        #expect(c1.position == Position(file: "Sources/Auth.swift", line: 22, lineType: .new))
    }

    @Test("a general, resolved finding has no position and isn't open")
    func generalFinding() throws {
        let report = try ReportParser.parse(sample)
        let g1 = try #require(report.findings.first { $0.id == "G1" })
        #expect(g1.scope == .general)
        #expect(g1.position == nil)
        #expect(!g1.isOpen)
        #expect(report.findings.count == 2)
    }

    @Test("missing review header throws")
    func missingHeader() {
        #expect(throws: ReportParser.ParseError.missingReviewHeader) {
            _ = try ReportParser.parse("# Just a document, no anchors here")
        }
    }
}
