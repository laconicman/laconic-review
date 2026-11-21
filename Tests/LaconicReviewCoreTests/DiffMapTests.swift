import XCTest
@testable import LaconicReviewCore

final class DiffMapTests: XCTestCase {
    /// Two hunks: mixed add/remove/context, then a second hunk further down the file.
    private let diff = """
    @@ -10,4 +10,5 @@
     ctx10
    -old11
    +new11
    +new12
     ctx12
     ctx13
    @@ -40,3 +41,3 @@
     ctx40
    -old41
    +new41
     ctx42
    """

    private func maps() -> [String: FileLineMap] {
        DiffParser.lineMaps(for: [FileDiff(oldPath: "a.swift", newPath: "a.swift", diff: diff)])
    }

    func testParsesAddedContextAndRemovedLines() {
        let lines = maps()["a.swift"]?.lines
        XCTAssertEqual(lines?[10], .context(oldLine: 10))
        XCTAssertEqual(lines?[11], .added)
        XCTAssertEqual(lines?[12], .added)
        XCTAssertEqual(lines?[13], .context(oldLine: 12))
        XCTAssertEqual(lines?[14], .context(oldLine: 13))
        // Second hunk keeps counting independently.
        XCTAssertEqual(lines?[41], .context(oldLine: 40))
        XCTAssertEqual(lines?[42], .added)
        XCTAssertEqual(lines?[43], .context(oldLine: 42))
        // Outside hunks: absent.
        XCTAssertNil(lines?[15])
        XCTAssertNil(lines?[44])
    }

    func testResolveAddedLineSendsNewSideOnly() {
        let position = Position(file: "a.swift", line: 11, lineType: .new)
        XCTAssertEqual(
            AnchorResolver.resolve(position, in: maps()),
            ResolvedPosition(newPath: "a.swift", newLine: 11)
        )
    }

    func testResolveContextLineSendsBothSides() {
        // The TD-7 case: an unchanged hunk line needs old_* + new_* together.
        let position = Position(file: "a.swift", line: 13, lineType: .new)
        XCTAssertEqual(
            AnchorResolver.resolve(position, in: maps()),
            ResolvedPosition(oldPath: "a.swift", newPath: "a.swift", oldLine: 12, newLine: 13)
        )
    }

    func testResolveOutsideDiffReturnsNil() {
        let position = Position(file: "a.swift", line: 99, lineType: .new)
        XCTAssertNil(AnchorResolver.resolve(position, in: maps()))
        // A file the MR doesn't touch at all.
        let other = Position(file: "b.swift", line: 1, lineType: .new)
        XCTAssertNil(AnchorResolver.resolve(other, in: maps()))
    }

    func testResolveOldSideRemovedLineSendsOldSideOnly() {
        // Old line 41 is the `-old41` removal in hunk two.
        let position = Position(file: "a.swift", line: 41, lineType: .old)
        XCTAssertEqual(
            AnchorResolver.resolve(position, in: maps()),
            ResolvedPosition(oldPath: "a.swift", oldLine: 41)
        )
    }

    func testResolveOldSideContextLineSendsBothSides() {
        // Old line 40 is ` ctx40` — unchanged, so it needs all four fields too.
        let position = Position(file: "a.swift", line: 40, lineType: .old)
        XCTAssertEqual(
            AnchorResolver.resolve(position, in: maps()),
            ResolvedPosition(oldPath: "a.swift", newPath: "a.swift", oldLine: 40, newLine: 41)
        )
    }

    func testResolveOldSideOutsideDiffReturnsNil() {
        let position = Position(file: "a.swift", line: 99, lineType: .old)
        XCTAssertNil(AnchorResolver.resolve(position, in: maps()))
    }

    func testRenamedFileResolvesByEitherPathAndKeepsOldPath() {
        let renamed = """
        @@ -1,2 +1,2 @@
         same
        -old name
        +new name
        """
        let diffs = [FileDiff(oldPath: "old.swift", newPath: "new.swift", diff: renamed)]
        let maps = DiffParser.lineMaps(for: diffs)
        // Both keys index the same map.
        XCTAssertNotNil(maps["old.swift"])
        XCTAssertNotNil(maps["new.swift"])

        // Context line in a renamed file: old_path must be the OLD name.
        let ctx = Position(file: "new.swift", line: 1, lineType: .new)
        XCTAssertEqual(
            AnchorResolver.resolve(ctx, in: maps),
            ResolvedPosition(oldPath: "old.swift", newPath: "new.swift", oldLine: 1, newLine: 1)
        )
    }

    func testEmptyContextLinesConsumeNumbersAndStayAnchorable() {
        // Git emits "" (no leading space) for empty context lines; GitLab emits " ".
        // Both consume a line on each side — and both are anchorable (GitLab
        // builds line codes from coordinates, not content).
        let diff = """
        @@ -1,3 +1,4 @@
         one

        +two
         three
        """
        let map = DiffParser.lineMaps(for: [FileDiff(oldPath: "f", newPath: "f", diff: diff)])["f"]
        XCTAssertEqual(map?.lines[1], .context(oldLine: 1))
        XCTAssertEqual(map?.lines[2], .context(oldLine: 2))   // the "" line
        XCTAssertEqual(map?.lines[3], .added)                 // "+two" — numbering held
        XCTAssertEqual(map?.lines[4], .context(oldLine: 3))
        XCTAssertEqual(map?.oldLines[2], .context(newLine: 2))
        XCTAssertEqual(map?.lines.count, 4)
    }

    func testCombiningMarkAfterPrefixDoesNotHideTheLineKind() {
        // A file line starting with a combining mark fuses it into the prefix
        // grapheme (" ́"); utf8 dispatch must still see the space.
        let diff = "@@ -1,3 +1,3 @@\n \u{301}mark\n ctx\n ctx\n"
        let map = DiffParser.lineMaps(for: [FileDiff(oldPath: "f", newPath: "f", diff: diff)])["f"]
        XCTAssertEqual(map?.lines[1], .context(oldLine: 1))
        XCTAssertEqual(map?.lines[2], .context(oldLine: 2))
        XCTAssertEqual(map?.lines[3], .context(oldLine: 3))
        XCTAssertEqual(map?.lines.count, 3)
    }

    func testHunkHeaderWithoutCountsAndNoNewlineMarker() {
        // `@@ -5 +5 @@` declares one line per side — the body must match.
        let diff = """
        @@ -5 +5 @@
        -five
        \\ No newline at end of file
        +five!
        \\ No newline at end of file
        """
        let map = DiffParser.lineMaps(for: [FileDiff(oldPath: "f", newPath: "f", diff: diff)])["f"]
        XCTAssertEqual(map?.lines[5], .added)
        XCTAssertEqual(map?.oldLines[5], .removed)
        XCTAssertEqual(map?.lines.count, 1)
        XCTAssertEqual(map?.oldLines.count, 1)
    }
}
