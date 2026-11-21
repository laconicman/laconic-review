import Foundation

/// One file's unified diff from the MR — the raw material for resolving line anchors.
public struct FileDiff: Equatable, Sendable {
    public let oldPath: String
    public let newPath: String
    /// Unified-diff hunks (`@@ … @@` sections), as returned by GitLab's diffs API.
    public let diff: String

    public init(oldPath: String, newPath: String, diff: String) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.diff = diff
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

/// One file's line maps on both sides of the diff, plus the old path (renames need
/// it for `old_path`).
public struct FileLineMap: Equatable, Sendable {
    public let oldPath: String
    public let newPath: String
    /// New-file line number → diff classification. Lines outside hunks are absent.
    public let lines: [Int: DiffLine]
    /// Old-file line number → diff classification. Lines outside hunks are absent.
    public let oldLines: [Int: OldDiffLine]
}

/// GitLab's ready-to-send `text` position: the four path/line fields it can carry.
/// `nil` fields are omitted from the request — e.g. an added line sends only `new_*`,
/// a context line sends both sides.
public struct ResolvedPosition: Equatable, Sendable {
    public var oldPath: String?
    public var newPath: String?
    public var oldLine: Int?
    public var newLine: Int?

    public init(oldPath: String? = nil, newPath: String? = nil, oldLine: Int? = nil, newLine: Int? = nil) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.oldLine = oldLine
        self.newLine = newLine
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
            let (lines, oldLines) = parse(diff.diff)
            let map = FileLineMap(
                oldPath: diff.oldPath, newPath: diff.newPath, lines: lines, oldLines: oldLines
            )
            maps[diff.newPath] = map
            if diff.oldPath != diff.newPath { maps[diff.oldPath] = map }
        }
        return maps
    }

    /// Walk the hunks of one file's diff, recording each line's classification on
    /// both sides. Lines outside hunks never appear — anchoring there is a
    /// guaranteed `badRequest`.
    static func parse(_ diff: String) -> (lines: [Int: DiffLine], oldLines: [Int: OldDiffLine]) {
        var lines: [Int: DiffLine] = [:]
        var oldLines: [Int: OldDiffLine] = [:]
        var oldLine = 0, newLine = 0, inHunk = false
        // A trailing "\n" leaves a phantom "" after the last real line — drop it
        // so it isn't counted as an empty context line.
        var rows = diff.components(separatedBy: "\n")
        if diff.hasSuffix("\n") { rows.removeLast() }
        for raw in rows {
            if raw.hasPrefix("@@") {
                guard let (o, n) = hunkStart(raw) else { inHunk = false; continue }
                oldLine = o; newLine = n; inHunk = true
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
        return (lines, oldLines)
    }

    /// `@@ -oldStart[,oldCount] +newStart[,newCount] @@ …` → (oldStart, newStart).
    private static func hunkStart(_ header: String) -> (Int, Int)? {
        let tokens = header.split(separator: " ")
        guard tokens.count >= 3,
              let old = Int(tokens[1].dropFirst().prefix { $0 != "," }),
              let new = Int(tokens[2].dropFirst().prefix { $0 != "," })
        else { return nil }
        return (old, new)
    }
}

/// Turns a report ``Position`` into the ``ResolvedPosition`` GitLab actually accepts.
public enum AnchorResolver {
    /// - `.new`/`.old` anchors are looked up in the diff symmetrically: an added or
    ///   removed line posts its own side only, a context line posts all four fields
    ///   (GitLab rejects a one-sided position on an unchanged line).
    /// - Returns `nil` when the anchor can't be expressed — the caller falls back
    ///   to a general note rather than letting GitLab reject the whole batch.
    public static func resolve(_ position: Position, in maps: [String: FileLineMap]) -> ResolvedPosition? {
        guard let line = position.line else { return nil }
        guard let map = maps[position.file] else { return nil }
        switch position.lineType {
        case .new:
            guard let kind = map.lines[line] else { return nil }
            switch kind {
            case .added:
                return ResolvedPosition(newPath: map.newPath, newLine: line)
            case .context(let oldLine):
                return ResolvedPosition(
                    oldPath: map.oldPath, newPath: map.newPath, oldLine: oldLine, newLine: line
                )
            }
        case .old:
            guard let kind = map.oldLines[line] else { return nil }
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
