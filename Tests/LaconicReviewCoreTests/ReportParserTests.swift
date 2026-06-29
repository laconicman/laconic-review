import Testing
@testable import LaconicReviewCore

@Suite("ReportParser")
struct ReportParserTests {
    // Ids are severity-initial mnemonics (B/C/N); scope is orthogonal, so a general-scoped
    // concern is still a `C`. `severity=` is authoritative; status uses the locked vocab.
    let sample = """
    <!-- review branch=fix/logout base=develop iid=965 iteration=2 skill=laconic-review@1 -->
    # Review for fix/logout

    <!-- finding id=C1 severity=concern status=open scope=line file=Sources/Auth.swift line=18-22 line_type=new links=C2 -->
    ### 🟡 C1. Token not cleared — ⏳ Open
    The session token survives logout.

    ```swift
    session.clear()
    ```

    <!-- finding id=C2 severity=concern status=closed scope=general -->
    ### 🟡 C2. Naming — ✅ Closed
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
        #expect(c1.links == ["C2"])
        #expect(c1.isOpen)
        #expect(c1.markdown.contains("survives logout"))
        #expect(c1.markdown.contains("session.clear()"))      // code fence preserved verbatim
        #expect(c1.position == Position(file: "Sources/Auth.swift", line: 22, lineType: .new))
    }

    @Test("a closed, general-scoped concern has no position and isn't open")
    func closedGeneralFinding() throws {
        let report = try ReportParser.parse(sample)
        let c2 = try #require(report.findings.first { $0.id == "C2" })
        #expect(c2.scope == .general)
        #expect(c2.severity == "concern")     // general scope, still a concern (no "G")
        #expect(c2.position == nil)
        #expect(!c2.isOpen)
        #expect(report.findings.count == 2)
    }

    @Test("missing review header throws")
    func missingHeader() {
        #expect(throws: ReportParser.ParseError.missingReviewHeader) {
            _ = try ReportParser.parse("# Just a document, no anchors here")
        }
    }

    @Test("anchor syntax quoted in prose is not treated as a real anchor")
    func ignoresInlineAnchorMentions() throws {
        let markdown = """
        <!-- review branch=b base=develop iid=1 -->
        > Machine fields live in `<!-- finding … -->`; everything above the first
        > `<!-- finding -->` is human front-matter the parser skips.

        <!-- finding id=C1 severity=concern status=open scope=general -->
        ### C1. Real
        body
        """
        let report = try ReportParser.parse(markdown)
        #expect(report.findings.count == 1)        // not 3 — the inline mentions are prose
        #expect(report.findings.first?.id == "C1")
    }

    @Test("line_type=old, single line, and empty links parse")
    func oldSideSingleLineNoLinks() throws {
        let markdown = """
        <!-- review branch=b base=develop iid=1 -->
        <!-- finding id=N1 severity=nit status=open scope=line file=A.swift line=5 line_type=old -->
        ### N1. removed line
        gone
        """
        let n1 = try #require(try ReportParser.parse(markdown).findings.first)
        #expect(n1.lineType == .old)
        #expect(n1.lineStart == 5)
        #expect(n1.lineEnd == nil)
        #expect(n1.links.isEmpty)
        #expect(n1.position == Position(file: "A.swift", line: 5, lineType: .old))
    }
}
