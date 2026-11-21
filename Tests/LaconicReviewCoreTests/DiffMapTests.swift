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

    func testResolveOutsideHunksMapsThroughOffsets() {
        // TD-9: unchanged lines outside every hunk resolve to both-side positions.
        // Fixture offsets: hunk1 adds +1 net (new 10-14 ↔ old 10-13), hunk2 adds
        // another +0... net +1 overall — gaps map old = new - 1 between/after.
        // Before hunk1 the offset is 0.
        let before = Position(file: "a.swift", line: 5, lineType: .new)
        XCTAssertEqual(
            AnchorResolver.resolve(before, in: maps()),
            ResolvedPosition(oldPath: "a.swift", newPath: "a.swift", oldLine: 5, newLine: 5, outsideHunks: true)
        )
        let between = Position(file: "a.swift", line: 20, lineType: .new)
        XCTAssertEqual(
            AnchorResolver.resolve(between, in: maps()),
            ResolvedPosition(oldPath: "a.swift", newPath: "a.swift", oldLine: 19, newLine: 20, outsideHunks: true)
        )
        let after = Position(file: "a.swift", line: 99, lineType: .new)
        XCTAssertEqual(
            AnchorResolver.resolve(after, in: maps()),
            ResolvedPosition(oldPath: "a.swift", newPath: "a.swift", oldLine: 98, newLine: 99, outsideHunks: true)
        )
        // A file the MR doesn't touch at all still can't resolve.
        let other = Position(file: "b.swift", line: 1, lineType: .new)
        XCTAssertNil(AnchorResolver.resolve(other, in: maps()))
    }

    func testResolveOldSideOutsideHunksMapsThroughOffsets() {
        // Mirror of the new-side case: old = new + offset inverted.
        let before = Position(file: "a.swift", line: 5, lineType: .old)
        XCTAssertEqual(
            AnchorResolver.resolve(before, in: maps()),
            ResolvedPosition(oldPath: "a.swift", newPath: "a.swift", oldLine: 5, newLine: 5, outsideHunks: true)
        )
        let between = Position(file: "a.swift", line: 20, lineType: .old)
        XCTAssertEqual(
            AnchorResolver.resolve(between, in: maps()),
            ResolvedPosition(oldPath: "a.swift", newPath: "a.swift", oldLine: 20, newLine: 21, outsideHunks: true)
        )
        let after = Position(file: "a.swift", line: 99, lineType: .old)
        XCTAssertEqual(
            AnchorResolver.resolve(after, in: maps()),
            ResolvedPosition(oldPath: "a.swift", newPath: "a.swift", oldLine: 99, newLine: 100, outsideHunks: true)
        )
    }

    func testOutOfHunkMappingNeedsCompleteDiffAndBothSides() {
        // too_large diffs may be truncated — offsets would lie.
        let partial = FileDiff(oldPath: "a.swift", newPath: "a.swift", diff: diff, tooLarge: true)
        let m = DiffParser.lineMaps(for: [partial])
        XCTAssertNil(AnchorResolver.resolve(Position(file: "a.swift", line: 20, lineType: .new), in: m))
        // collapsed is only a UI fold — the diff text is complete, mapping holds.
        let folded = FileDiff(oldPath: "a.swift", newPath: "a.swift", diff: diff, collapsed: true)
        let fm = DiffParser.lineMaps(for: [folded])
        XCTAssertEqual(
            AnchorResolver.resolve(Position(file: "a.swift", line: 20, lineType: .new), in: fm),
            ResolvedPosition(oldPath: "a.swift", newPath: "a.swift", oldLine: 19, newLine: 20, outsideHunks: true)
        )
        // Added file: no old side exists to pair coordinates with.
        let added = FileDiff(oldPath: "a.swift", newPath: "a.swift", diff: diff, newFile: true)
        let am = DiffParser.lineMaps(for: [added])
        XCTAssertNil(AnchorResolver.resolve(Position(file: "a.swift", line: 20, lineType: .new), in: am))
        // Deleted file: no new side.
        let deleted = FileDiff(oldPath: "a.swift", newPath: "a.swift", diff: diff, deletedFile: true)
        let dm = DiffParser.lineMaps(for: [deleted])
        XCTAssertNil(AnchorResolver.resolve(Position(file: "a.swift", line: 20, lineType: .old), in: dm))
        // Empty diff (binary/mode-only, or collapsed-with-patch-omitted):
        // no hunks, no correspondence.
        let empty = DiffParser.lineMaps(for: [FileDiff(oldPath: "a.swift", newPath: "a.swift", diff: "")])
        XCTAssertNil(AnchorResolver.resolve(Position(file: "a.swift", line: 20, lineType: .new), in: empty))
        let collapsedEmpty = DiffParser.lineMaps(for: [
            FileDiff(oldPath: "a.swift", newPath: "a.swift", diff: "", collapsed: true)
        ])
        XCTAssertNil(AnchorResolver.resolve(Position(file: "a.swift", line: 20, lineType: .new), in: collapsedEmpty))
    }

    func testLineInsideHunkRangeButUnclassifiedStillDemotes() {
        // A truncated diff declares hunk coverage the body never fills — the
        // missing new lines sit inside the hunk's range, so offset mapping
        // must not pretend they're unchanged.
        let truncated = "@@ -10,4 +10,5 @@\n ctx10\n"
        let m = DiffParser.lineMaps(for: [FileDiff(oldPath: "a.swift", newPath: "a.swift", diff: truncated)])
        XCTAssertNil(AnchorResolver.resolve(Position(file: "a.swift", line: 12, lineType: .new), in: m))
        // …but a line past the hunk still maps.
        XCTAssertEqual(
            AnchorResolver.resolve(Position(file: "a.swift", line: 20, lineType: .new), in: m),
            ResolvedPosition(oldPath: "a.swift", newPath: "a.swift", oldLine: 19, newLine: 20, outsideHunks: true)
        )
    }

    func testCountZeroHunkKeepsBoundaryLineInTheGap() {
        // `@@ -3,0 +4,2 @@` (verified against git -U0): insertion after old
        // line 3 — old line 3 is unchanged and must map with offset 0, while
        // old line 4 maps past the hunk.
        let ins = "@@ -3,0 +4,2 @@\n+NEWa\n+NEWb\n"
        let m = DiffParser.lineMaps(for: [FileDiff(oldPath: "f", newPath: "f", diff: ins)])["f"]
        // new 3 ↔ old 3 (before the insertion), new 6 ↔ old 4 (after it).
        XCTAssertEqual(
            AnchorResolver.resolve(Position(file: "f", line: 3, lineType: .new), in: ["f": m!]),
            ResolvedPosition(oldPath: "f", newPath: "f", oldLine: 3, newLine: 3, outsideHunks: true)
        )
        XCTAssertEqual(
            AnchorResolver.resolve(Position(file: "f", line: 6, lineType: .new), in: ["f": m!]),
            ResolvedPosition(oldPath: "f", newPath: "f", oldLine: 4, newLine: 6, outsideHunks: true)
        )
    }

    func testCountZeroNewSideHunkKeepsBoundaryLineInTheGap() {
        // Mirror: `@@ -3 +2,0 @@` (git -U0 verified) deletes old line 3 — new
        // line 2 stays in the gap, new line 3 is the following unchanged line.
        let del = "@@ -3 +2,0 @@\n-l3\n"
        let m = DiffParser.lineMaps(for: [FileDiff(oldPath: "f", newPath: "f", diff: del)])["f"]
        XCTAssertEqual(
            AnchorResolver.resolve(Position(file: "f", line: 2, lineType: .new), in: ["f": m!]),
            ResolvedPosition(oldPath: "f", newPath: "f", oldLine: 2, newLine: 2, outsideHunks: true)
        )
        XCTAssertEqual(
            AnchorResolver.resolve(Position(file: "f", line: 3, lineType: .new), in: ["f": m!]),
            ResolvedPosition(oldPath: "f", newPath: "f", oldLine: 4, newLine: 3, outsideHunks: true)
        )
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

    func testCRLFDiffKeepsCountingAndDropsThePhantomRow() {
        // CRLF patch: every row carries "\r"; the terminator still leaves one
        // phantom "" — and "\r\n" being a single grapheme must not matter. The
        // bare "\r\n" row is git's empty-context quirk: after stripping it must
        // still count as a context line on both sides.
        let diff = "@@ -1,3 +1,4 @@\r\n ctx\r\n\r\n+new\r\n ctx\r\n"
        let map = DiffParser.lineMaps(for: [FileDiff(oldPath: "f", newPath: "f", diff: diff)])["f"]
        XCTAssertEqual(map?.lines[1], .context(oldLine: 1))
        XCTAssertEqual(map?.lines[2], .context(oldLine: 2))   // bare "\r" row
        XCTAssertEqual(map?.lines[3], .added)                 // "+new" — numbering held
        XCTAssertEqual(map?.lines[4], .context(oldLine: 3))
        XCTAssertEqual(map?.lines.count, 4)   // no phantom 5th row
        // Old side too — a regression there would pass the checks above.
        XCTAssertEqual(map?.oldLines[1], .context(newLine: 1))
        XCTAssertEqual(map?.oldLines[2], .context(newLine: 2))
        XCTAssertEqual(map?.oldLines[3], .context(newLine: 4))
        XCTAssertEqual(map?.oldLines.count, 3)
    }

    func testFallbackToGeneralNoteNeedsDefinite400OnInferredAnchor() {
        // Only a definite position rejection of an *inferred* anchor may retry
        // as a general note — anything else risks double-posting.
        let inferred = ResolvedPosition(
            oldPath: "a.swift", newPath: "a.swift", oldLine: 5, newLine: 5, outsideHunks: true
        )
        let observed = ResolvedPosition(newPath: "a.swift", newLine: 11)
        XCTAssertTrue(DiscussionPostError.shouldFallbackToGeneralNote(
            error: DiscussionPostError.httpStatus(400), anchor: inferred))
        XCTAssertFalse(DiscussionPostError.shouldFallbackToGeneralNote(
            error: DiscussionPostError.httpStatus(400), anchor: observed))   // in-diff: real bug, don't mask
        XCTAssertFalse(DiscussionPostError.shouldFallbackToGeneralNote(
            error: DiscussionPostError.httpStatus(400), anchor: nil))
        XCTAssertFalse(DiscussionPostError.shouldFallbackToGeneralNote(
            error: DiscussionPostError.httpStatus(500), anchor: inferred))  // ambiguous — may have committed
        XCTAssertFalse(DiscussionPostError.shouldFallbackToGeneralNote(
            error: URLError(.timedOut), anchor: inferred))                  // transport — may have committed
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
