import Foundation

/// A code-review report parsed from the markdown SSOT: the review header plus its findings.
///
/// The markdown is the human-editable source of truth; machine fields live in one HTML
/// comment per finding (and one for the report). SHAs are deliberately absent — `publish`
/// fetches `diff_refs` fresh from the server. See ``ReportParser``.
public struct ReviewReport: Equatable, Sendable {
    public let header: ReviewHeader
    public let findings: [Finding]

    public init(header: ReviewHeader, findings: [Finding]) {
        self.header = header
        self.findings = findings
    }
}

/// The `<!-- review … -->` anchor: which MR/iteration this report targets.
public struct ReviewHeader: Equatable, Sendable {
    public let branch: String
    public let base: String
    public let iid: Int
    public let iteration: Int
    public let skill: String

    public init(branch: String, base: String, iid: Int, iteration: Int, skill: String) {
        self.branch = branch
        self.base = base
        self.iid = iid
        self.iteration = iteration
        self.skill = skill
    }
}

/// Where a finding attaches: a specific diff line, or the merge request as a whole.
public enum FindingScope: String, Sendable, Equatable, Codable {
    case line
    case general
}

/// Which side of the diff a line anchor refers to (`new_line` vs `old_line`).
public enum LineSide: String, Sendable, Equatable, Codable {
    case new
    case old
}

/// One review finding: the machine fields from its `<!-- finding … -->` anchor, plus the
/// verbatim markdown block (heading + prose) that becomes the published discussion body.
public struct Finding: Equatable, Sendable {
    public let id: String
    public let severity: String
    public let status: String
    public let scope: FindingScope
    public let file: String?
    public let lineStart: Int?
    public let lineEnd: Int?
    public let lineType: LineSide
    public let links: [String]
    /// The verbatim prose block (heading + body), posted to GitLab unmodified.
    public let markdown: String

    public init(
        id: String, severity: String, status: String, scope: FindingScope,
        file: String?, lineStart: Int?, lineEnd: Int?, lineType: LineSide,
        links: [String], markdown: String
    ) {
        self.id = id; self.severity = severity; self.status = status; self.scope = scope
        self.file = file; self.lineStart = lineStart; self.lineEnd = lineEnd
        self.lineType = lineType; self.links = links; self.markdown = markdown
    }

    /// Unresolved findings are the ones `publish` posts.
    public var isOpen: Bool { status.lowercased() == "open" }

    /// The diff anchor for a line-scoped finding (the *end* line, where review threads attach),
    /// or `nil` for a general finding or one missing its file/line.
    public var position: Position? {
        guard scope == .line, let file, let line = lineEnd ?? lineStart else { return nil }
        return Position(file: file, line: line, lineType: lineType)
    }
}
