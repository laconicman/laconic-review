import Foundation

/// One file's unified diff from the MR — the raw material for resolving line anchors.
public struct FileDiff: Equatable, Sendable {
    public let oldPath: String
    public let newPath: String
    /// Unified-diff hunks (`@@ … @@` sections), as returned by GitLab's diffs API.
    public let diff: String
    /// GitLab's file flags — they gate whether out-of-hunk offset mapping is safe.
    public let newFile: Bool
    public let deletedFile: Bool
    /// `too_large` means the diff text may be truncated — hunk offsets can't be
    /// trusted to describe the whole file. (`collapsed` is only a UI fold; the
    /// diff itself is still complete.)
    public let collapsed: Bool
    public let tooLarge: Bool

    public init(
        oldPath: String, newPath: String, diff: String,
        newFile: Bool = false, deletedFile: Bool = false,
        collapsed: Bool = false, tooLarge: Bool = false
    ) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.diff = diff
        self.newFile = newFile
        self.deletedFile = deletedFile
        self.collapsed = collapsed
        self.tooLarge = tooLarge
    }
}

/// What a new-file line is inside its file's diff.
public enum DiffLine: Equatable, Sendable {
    /// `+` line — exists only on the new side.
    case added
    /// ` ` context line — unchanged, present on both sides; carries its old-side number.
    case context(oldLine: Int)
}

/// What an old-file line is inside its file's diff.
public enum OldDiffLine: Equatable, Sendable {
    /// `-` line — exists only on the old side.
    case removed
    /// ` ` context line — unchanged; carries its new-side number.
    case context(newLine: Int)
}

/// One hunk's covered line ranges on both sides of the diff, end-exclusive.
/// A count-0 side collapses to the empty interval just past its start line —
/// that line itself stays in the unchanged gap before the hunk.
public struct DiffHunk: Equatable, Sendable {
    public let oldRange: Range<Int>
    public let newRange: Range<Int>
}

/// One file's line maps on both sides of the diff, plus the old path (renames need
/// it for `old_path`).
public struct FileLineMap: Equatable, Sendable {
    public let oldPath: String
    public let newPath: String
    /// New-file line number → diff classification. Lines outside hunks are absent.
    public let lines: [Int: DiffLine]
    /// Old-file line number → diff classification. Lines outside hunks are absent.
    public let oldLines: [Int: OldDiffLine]
    /// Covered ranges of every hunk, in file order — the skeleton for mapping
    /// unchanged lines that fall outside all of them.
    public let hunks: [DiffHunk]
    /// False for an added file — there is no old side to send coordinates for.
    public let hasOldSide: Bool
    /// False for a deleted file — there is no new side.
    public let hasNewSide: Bool
    /// False when GitLab flagged the diff `too_large` — a possibly-truncated diff
    /// makes offset mapping untrustworthy. `collapsed` doesn't gate: it's a UI
    /// fold, the diff text is still complete.
    public let diffComplete: Bool

    /// Both files exist, the diff is whole, and at least one hunk anchors the offsets.
    var canMapOutsideHunks: Bool {
        hasOldSide && hasNewSide && diffComplete && !hunks.isEmpty
    }

    /// Old-file line for a new-file line outside every hunk. Unchanged regions
    /// between/around hunks share a constant offset; nil when unmappable —
    /// including a line inside a hunk's range that the maps somehow missed.
    func oldLine(forNewLine new: Int) -> Int? {
        guard canMapOutsideHunks, new >= 1 else { return nil }
        var newCursor = 1, oldCursor = 1
        for hunk in hunks {
            if new < hunk.newRange.lowerBound {
                let old = new - (newCursor - oldCursor)
                return old > 0 ? old : nil
            }
            if hunk.newRange.contains(new) { return nil }
            newCursor = hunk.newRange.upperBound
            oldCursor = hunk.oldRange.upperBound
        }
        let old = new - (newCursor - oldCursor)
        return old > 0 ? old : nil
    }

    /// New-file line for an old-file line outside every hunk — the mirror of
    /// ``oldLine(forNewLine:)``.
    func newLine(forOldLine old: Int) -> Int? {
        guard canMapOutsideHunks, old >= 1 else { return nil }
        var oldCursor = 1, newCursor = 1
        for hunk in hunks {
            if old < hunk.oldRange.lowerBound {
                let new = old + (newCursor - oldCursor)
                return new > 0 ? new : nil
            }
            if hunk.oldRange.contains(old) { return nil }
            oldCursor = hunk.oldRange.upperBound
            newCursor = hunk.newRange.upperBound
        }
        let new = old + (newCursor - oldCursor)
        return new > 0 ? new : nil
    }
}

/// GitLab's ready-to-send `text` position: the four path/line fields it can carry.
/// `nil` fields are omitted from the request — e.g. an added line sends only `new_*`,
/// a context line sends both sides.
public struct ResolvedPosition: Equatable, Sendable {
    public var oldPath: String?
    public var newPath: String?
    public var oldLine: Int?
    public var newLine: Int?
    /// True when the position was inferred for an unchanged line outside every
    /// hunk — computed, not observed in the diff. GitLab can still reject these
    /// (its blob-unfold path has size caps), so a caller may retry as a general
    /// note on a definite position rejection.
    public var outsideHunks: Bool

    public init(
        oldPath: String? = nil, newPath: String? = nil,
        oldLine: Int? = nil, newLine: Int? = nil, outsideHunks: Bool = false
    ) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.oldLine = oldLine
        self.newLine = newLine
        self.outsideHunks = outsideHunks
    }
}

/// Parses MR file diffs into per-file new-side line maps and resolves report anchors
/// against them — the provider-neutral half of context-line positions (TD-7).
public enum DiffParser {
    /// Index every file's new-side lines, keyed by `new_path` (and `old_path` too, so a
    /// renamed file still resolves when the report names either side).
    public static func lineMaps(for diffs: [FileDiff]) -> [String: FileLineMap] {
        var maps: [String: FileLineMap] = [:]
        for diff in diffs {
            let (lines, oldLines, hunks) = parse(diff.diff)
            let map = FileLineMap(
                oldPath: diff.oldPath, newPath: diff.newPath,
                lines: lines, oldLines: oldLines,
                hunks: hunks.sorted { $0.newRange.lowerBound < $1.newRange.lowerBound },
                hasOldSide: !diff.newFile, hasNewSide: !diff.deletedFile,
                diffComplete: !diff.tooLarge
            )
            maps[diff.newPath] = map
            if diff.oldPath != diff.newPath { maps[diff.oldPath] = map }
        }
        return maps
    }

    /// Walk the hunks of one file's diff, recording each line's classification on
    /// both sides plus every hunk's covered ranges. Lines outside hunks never
    /// appear in the maps — they resolve through hunk offsets instead (TD-9).
    static func parse(_ diff: String) -> (lines: [Int: DiffLine], oldLines: [Int: OldDiffLine], hunks: [DiffHunk]) {
        var lines: [Int: DiffLine] = [:]
        var oldLines: [Int: OldDiffLine] = [:]
        var hunks: [DiffHunk] = []
        var oldLine = 0, newLine = 0, inHunk = false
        // Normalize CRLF: rows keep a trailing "\r" that would hide an empty
        // context line ("\r" alone) from the bare-"" check below. Then drop the
        // phantom "" a trailing newline leaves after the last real line —
        // `hasSuffix("\n")` can't be used: "\r\n" is one grapheme cluster.
        var rows = diff.components(separatedBy: "\n").map {
            $0.hasSuffix("\r") ? String($0.dropLast()) : $0
        }
        if rows.count > 1, rows.last == "" { rows.removeLast() }
        for raw in rows {
            if raw.hasPrefix("@@") {
                guard let (oldRange, newRange) = hunkRanges(raw) else { inHunk = false; continue }
                oldLine = oldRange.lowerBound; newLine = newRange.lowerBound
                inHunk = true
                hunks.append(DiffHunk(oldRange: oldRange, newRange: newRange))
                continue
            }
            guard inHunk else { continue }
            // Git may emit a bare "" for an empty context line (no leading space);
            // it still consumes one line on each side. GitLab anchors by line
            // coordinates, not content — blank lines are publishable.
            if raw.isEmpty {
                lines[newLine] = .context(oldLine: oldLine)
                oldLines[oldLine] = .context(newLine: newLine)
                oldLine += 1; newLine += 1
                continue
            }
            // utf8, not Character: a leading combining mark would fuse with the
            // prefix into one grapheme and hide it from `raw.first`.
            switch raw.utf8.first {
            case UInt8(ascii: "+"): lines[newLine] = .added; newLine += 1
            case UInt8(ascii: "-"): oldLines[oldLine] = .removed; oldLine += 1
            case UInt8(ascii: " "):
                lines[newLine] = .context(oldLine: oldLine)
                oldLines[oldLine] = .context(newLine: newLine)
                newLine += 1; oldLine += 1
            default: break   // "\ No newline…", malformed — consume nothing
            }
        }
        return (lines, oldLines, hunks)
    }

    /// `@@ -oldStart[,oldCount] +newStart[,newCount] @@ …` → the covered line
    /// ranges on both sides (a missing count means 1). A zero count means the
    /// hunk is positioned *after* that line — the covered range is the empty
    /// interval at `start + 1`, keeping the boundary line in the unchanged gap.
    private static func hunkRanges(_ header: String) -> (old: Range<Int>, new: Range<Int>)? {
        let tokens = header.split(separator: " ")
        guard tokens.count >= 3,
              let (os, oc) = rangeSpec(tokens[1]),
              let (ns, nc) = rangeSpec(tokens[2])
        else { return nil }
        return (
            old: oc == 0 ? (os + 1)..<(os + 1) : os..<(os + oc),
            new: nc == 0 ? (ns + 1)..<(ns + 1) : ns..<(ns + nc)
        )
    }

    /// `-286,6` / `-286` (count defaults to 1) → (start, count).
    private static func rangeSpec(_ token: Substring) -> (Int, Int)? {
        let parts = token.dropFirst().split(separator: ",")
        guard let start = Int(parts[0]) else { return nil }
        if parts.count == 1 { return (start, 1) }
        guard let count = Int(parts[1]), count >= 0 else { return nil }
        return (start, count)
    }
}

/// Turns a report ``Position`` into the ``ResolvedPosition`` GitLab actually accepts.
public enum AnchorResolver {
    /// - `.new`/`.old` anchors are looked up in the diff symmetrically: an added or
    ///   removed line posts its own side only, a context line posts all four fields
    ///   (GitLab rejects a one-sided position on an unchanged line).
    /// - A line outside every hunk is unchanged by definition — it resolves through
    ///   the hunk offsets to a both-sides position (GitLab 19.5.3 accepts those;
    ///   verified live). Added/deleted files, `too_large` diffs, and empty diffs
    ///   still return `nil` — there is no trustworthy correspondence.
    /// - Returns `nil` when the anchor can't be expressed — the caller falls back
    ///   to a general note rather than letting GitLab reject the whole batch.
    public static func resolve(_ position: Position, in maps: [String: FileLineMap]) -> ResolvedPosition? {
        guard let line = position.line else { return nil }
        guard let map = maps[position.file] else { return nil }
        switch position.lineType {
        case .new:
            guard let kind = map.lines[line] else {
                guard let oldLine = map.oldLine(forNewLine: line) else { return nil }
                return ResolvedPosition(
                    oldPath: map.oldPath, newPath: map.newPath,
                    oldLine: oldLine, newLine: line, outsideHunks: true
                )
            }
            switch kind {
            case .added:
                return ResolvedPosition(newPath: map.newPath, newLine: line)
            case .context(let oldLine):
                return ResolvedPosition(
                    oldPath: map.oldPath, newPath: map.newPath, oldLine: oldLine, newLine: line
                )
            }
        case .old:
            guard let kind = map.oldLines[line] else {
                guard let newLine = map.newLine(forOldLine: line) else { return nil }
                return ResolvedPosition(
                    oldPath: map.oldPath, newPath: map.newPath,
                    oldLine: line, newLine: newLine, outsideHunks: true
                )
            }
            switch kind {
            case .removed:
                return ResolvedPosition(oldPath: map.oldPath, oldLine: line)
            case .context(let newLine):
                return ResolvedPosition(
                    oldPath: map.oldPath, newPath: map.newPath, oldLine: line, newLine: newLine
                )
            }
        case .file:
            return nil
        }
    }
}
