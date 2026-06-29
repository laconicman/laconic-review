# Report format

The review report is the **human-editable single source of truth** for a code review: prose a
human freely edits, with machine fields in HTML-comment anchors that `laconic-review publish`
parses into GitLab discussions.

This document is the **human formulation** of that format. The **executable** truth is
`LaconicReviewCore` — `ReportParser` (grammar) plus `Finding` / `ReviewHeader` (fields, with
their DocC). A working example is [`Samples/example-report.md`](../Samples/example-report.md).
If this doc and the parser ever disagree, the parser wins — fix the doc.

> **Why this lives in the connector, not the skill.** The connector *owns* the format — its
> parser defines it. The review skill is a consumer: it references this document and conforms.
> One source of truth, read from two angles (parser/DocC for machines, this file for humans).

## Anatomy

A report is, in order:

1. **One `<!-- review … -->` anchor** — which MR / iteration this report targets.
2. **Human front-matter** — everything between the review anchor and the first
   `<!-- finding … -->`. **The parser ignores it.** This is free space for a title, a TL;DR, a
   summary table, a merge recommendation — none of it is published.
3. **Findings, back-to-back** — each a `<!-- finding … -->` anchor immediately followed by its
   prose. A finding's prose runs **from its anchor to the next anchor** (or end of file).

Rule 3 has a sharp edge: **anything placed between two findings, or after the last finding,
becomes part of the preceding finding's published comment.** So do **not** put `##`-section
headers between findings, and put nothing after the last one. Group and summarize in the
front-matter instead — it's seen only by humans.

Each finding's prose is posted to GitLab **verbatim** (heading, body, code fences, links), so
write each block to stand alone as a comment, and keep sources **inline** in the finding rather
than in a trailing "Sources" section.

## Anchor grammar (what the parser enforces)

An anchor is a **single-line** HTML comment: `<!--`, a space, the keyword (`review` or
`finding`), a space, then space-separated `key=value` pairs, then `-->`.

> **Values contain no spaces.** The parser splits attributes on whitespace, so every value —
> paths, branches, line ranges, link lists — must be space-free. File paths and branch names
> already are; just don't wrap or pretty-print them.

### `<!-- review … -->`

| Key | Required | Meaning |
|---|:---:|---|
| `branch` | ✅ | Source branch under review. |
| `base` | ✅ | Base branch the MR targets (e.g. `develop`). |
| `iid` | ✅ | MR internal id. Use `0` before an MR exists (pre-MR review). |
| `iteration` | — | Review pass number (default `1`). |
| `skill` | — | Emitting skill + version, e.g. `laconic-review@1`. |

### `<!-- finding … -->`

| Key | Required | Default | Meaning |
|---|:---:|---|---|
| `id` | ◻︎ | `""` | Stable finding id (`C1`, `N3`). **Stable across iterations** — the lineage key. |
| `severity` | ◻︎ | `""` | `blocker` \| `concern` \| `nit`. |
| `status` | — | `open` | `open` \| `in_progress` \| `closed` \| `needs_info`. Only `open` is published. |
| `scope` | — | `general` | `line` (anchored to a diff line) \| `general` (top-level MR note). |
| `file` | line only | — | Repo-relative path. Required when `scope=line`. |
| `line` | line only | — | `start-end` or `start`. The thread anchors at the **end** line. |
| `line_type` | — | `new` | `new` (added/context → `new_line`) \| `old` (removed → `old_line`). |
| `links` | — | `[]` | Comma-separated finding ids this one relates to, e.g. `links=C1,N3`. |

◻︎ = the parser tolerates absence (it defaults), but a well-formed report always sets it, and
`lint` flags the omission.

**Line range.** `line=18-22` → start 18, end 22; `line=18` → single line. The published thread
attaches at the **end** line (`lineEnd ?? lineStart`).

## Conventions (what the skill emits, beyond syntax)

- **Severity → emoji:** 🔴 `blocker` · 🟡 `concern` · 🟢 `nit`.
- **Status → emoji:** ⏳ `open` · 🛠️ `in_progress` · ✅ `closed` · ❓ `needs_info`.
- **Finding ids** are `<severity-initial><n>` — **B**locker, **C**oncern, **N**it (`B1`, `C3`,
  `N2`). The prefix is a *birth mnemonic*; the authoritative current severity is the `severity=`
  field (it wins on conflict), so the id stays frozen for lineage even if severity is later
  revised. There is **no letter for scope**: a general-scoped concern is still `C<n>` with
  `scope=general`.
- **The anchor is the source of truth.** The heading (`### 🟡 C1. … — ⏳ Open`) mirrors the
  anchor's `severity`/`status` for humans; the parser reads only the anchor. Keep them in sync;
  on conflict, the anchor wins.
- **Scope.** `line` findings need `file` + `line` and post as line-anchored threads; `general`
  findings post as top-level MR notes.
- **Sources** go inline in the finding's prose (each travels with its comment), never in a
  trailing section.
- **Multi-file finding:** anchor the primary `file`; mention the others in prose.
- **Lineage / iterations:** `id` is stable across passes so re-review updates the same thread. A
  finding **closed with nuance** ⇒ open a **new** finding and `links=` both, rather than silently
  reopening the old one.
- **Cross-links (MVP):** `links` resolve to URLs only for findings already posted earlier in the
  same `publish` run; a link to a not-yet-posted finding renders as a bare id. A two-pass publish
  can fix this later.

## Not in the report (by design)

- **`diff_refs` / SHAs** — `publish` fetches `base/head/start_sha` fresh from the MR; the report
  carries only the stable anchor (`file` + `line` + `line_type`).
- **Publish state** — the id → discussion-url map lives in `<N>.published.json` beside the report
  (idempotency + cross-link resolution), not in the markdown.

## Validation

`laconic-review lint <report>` — offline, no token or network — rejects (non-zero exit) a report that:

- has no `<!-- review … -->` anchor, or is missing `branch` / `base` / `iid`;
- has a `scope=line` finding without `file` or `line` (it would silently degrade to a general note);
- uses an unknown `severity` / `status` token;
- has `links=` pointing at ids no finding declares;
- (warn) places a `##` header or other content between or after findings, which would leak into a
  comment body.

The skill's final step runs this and self-heals on failure.

## Invariants (the inviolable bits)

1. Edit prose freely; **never** edit the `<!-- review … -->` / `<!-- finding … -->` anchors.
2. Anchor values are space-free.
3. The anchor is the machine source of truth; the heading is a human mirror.
4. Findings are back-to-back; group and summarize only in the front-matter.
5. Anchors are **block-level** — each starts a line (after optional indentation). The parser
   ignores `<!-- … -->` mentioned inline in prose or backticks, so a report may document its own
   format (this one does).

## Decisions (locked)

- **Sectioning — back-to-back (Invariant 4).** No `## severity` sections between findings; the
  front-matter summary table carries human grouping. (Considered and declined: the example reads
  cleanly back-to-back, and a single grammar rule is easier for the skill to emit and lint to check.)
- **`iid` — required; use `0`** for a pre-MR review. A clearer contract than making it optional.
- **Status token — `closed`** (not `resolved`); fixtures updated.

## Still open

- **Cross-link two-pass.** `links` resolve to URLs only for findings posted earlier in the same
  run (see Conventions). The fix is a second pass that rewrites `links=` to URLs once all threads
  exist; the example's cross-link cycle is a ready test for it.
