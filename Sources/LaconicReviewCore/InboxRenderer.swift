import Foundation

/// Renders an ``Inbox`` as the anchored markdown an agent (or human) reads.
///
/// Same contract as the review report: machine fields in single-line HTML-comment anchors
/// with space-free `key=value` pairs (`<!-- inbox … -->` / `<!-- thread … -->`); prose is
/// for humans. A thread's notes render verbatim, in order, under a `### T<n>` heading the
/// anchor mirrors for humans (`no=`).
public enum InboxRenderer {

    /// The whole inbox file: one `inbox` anchor, human front-matter, then threads
    /// back-to-back — each its `<!-- thread … -->` anchor followed by the notes.
    public static func render(_ inbox: Inbox) -> String {
        var out: [String] = []
        let open = inbox.openCount
        let resolved = inbox.resolvedCount
        out.append("<!-- inbox iid=\(inbox.iid) branch=\(inbox.branch) fetched_at=\(iso8601(inbox.fetchedAt)) open=\(open) resolved=\(resolved) -->")
        out.append("")
        out.append("# Inbox — MR !\(inbox.iid) «\(inbox.title)»")
        out.append("")
        var summary = "\(open) open · \(resolved) resolved · \(inbox.threads.count) thread(s)"
        if let url = inbox.webURL { summary += " — \(url)" }
        out.append(summary)
        out.append("")
        out.append("Reply in a thread: `laconic-review reply \(inbox.iid) <discussion-id> --body \"…\" --confirm` (add `--resolve` to close it).")
        out.append("")

        for (offset, thread) in inbox.threads.enumerated() {
            out.append(threadBlock(thread, number: offset + 1))
            out.append("")
        }
        return out.joined(separator: "\n")
    }

    /// One thread: its anchor, `### T<n>` heading, then every note verbatim in order.
    static func threadBlock(_ thread: DiscussionThread, number: Int) -> String {
        var anchor = "<!-- thread id=\(thread.id) no=\(number) state=\(state(thread)) resolvable=\(thread.resolvable)"
        if let position = thread.position {
            anchor += " file=\(anchorPath(position.file))"
            if let line = position.line { anchor += " line=\(line)" }
            anchor += " line_type=\(position.lineType.rawValue)"
        }
        anchor += " -->"

        let heading = "### T\(number) · \(location(thread)) — \(stateEmoji(thread)) \(state(thread))"
        let notes = thread.notes.map(noteBlock).joined(separator: "\n\n")
        return [anchor, heading, "", notes].joined(separator: "\n")
    }

    static func noteBlock(_ note: ThreadNote) -> String {
        var header = "**\(note.author.isEmpty ? "?" : note.author)**"
        if !note.username.isEmpty { header += " (@\(note.username))" }
        if let created = note.createdAt { header += ", \(utc(created))" }
        return "\(header):\n\n\(note.body)"
    }

    static func state(_ thread: DiscussionThread) -> String {
        thread.resolved ? "resolved" : (thread.resolvable ? "open" : "note")
    }

    static func stateEmoji(_ thread: DiscussionThread) -> String {
        thread.resolved ? "✅" : (thread.resolvable ? "⏳" : "💬")
    }

    /// Anchor values are space-free `key=value` — a path containing spaces would silently
    /// truncate at the first space, so percent-encode everything outside a path-safe set.
    static func anchorPath(_ path: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~/")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }

    static func location(_ thread: DiscussionThread) -> String {
        guard let position = thread.position else { return "general" }
        let base = (position.file as NSString).lastPathComponent
        return position.line.map { "\(base):\($0)" } ?? "\(base) (file)"
    }

    static func iso8601(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02dZ", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
    }

    static func utc(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02d %02d:%02d UTC", c.year!, c.month!, c.day!, c.hour!, c.minute!)
    }
}
