# Tech debt

Numbered register. Each item carries what it costs and the change that retires it.

## Overview

Status legend: **open** (accepted, unscheduled) · **deferred** (a decision not to fix it
yet, with the reason).

### TD-1 — the skill is vendored in two places · open

`skills/laconic-code-review/` is canonical here and copied byte-identical into
`~/.claude/skills/`. Nothing enforces that they match.

**Cost.** A fix applied to one copy is invisible in the other, and the copy that runs is
the vendored one.

**Discharge.** Ship the repo as a Claude plugin (`.claude-plugin/plugin.json`), which
`UPSTREAM.md` already names as the intent, and retire the vendored copy.

### TD-2 — no `kind` axis · open

See <doc:Roadmap>. A finding that requests verification, or reports a security concern,
has to be mis-rated as a severity to be filed at all.

**Cost.** Measured on a real contribution: three of 25 findings in three rounds had no
correct rating available.

**Discharge.** A new optional anchor field, decoded as absent when missing so older
reports stay readable. Model the **taxonomy** Devin's public docs describe — categories
(bug / security / flag), severity within a category, and an intent axis for flags — not
its emoji or its embedded metadata values, which it confirmed are not a supported
external contract.

### TD-3 — `resolve-thread` posts no prose · open

Resolution flips a flag without saying what changed.

**Cost.** A contributor-side audit cannot distinguish *the reviewer confirmed this* from
*the author claimed it* — which is exactly the distinction the companion `contributions`
skill depends on to close a round.

**Discharge.** Accept a reason and post it as the resolving reply.

### TD-4 — superseded iterations carry no marker · open

Earlier published threads stay as they were when a new iteration lands.

**Cost.** A reader on iteration 2's thread has no signal that iteration 3 exists, and the
reader most likely to be there is the author, mid-round.

**Discharge.** <doc:Roadmap> item 2.

### TD-5 — GitHub is unsupported · deferred

``GitLabConnection`` is the only seam, by design.

**Cost.** The conventions worth adopting from Devin Review were all observed on GitHub,
and cannot be exercised here until a GitHub connection exists.

**Deferred** until there is a GitHub review to run against; the neutral core means this is
an addition, not a rewrite.

### TD-6 — `publish` aborts the batch on the first bad position · discharged

`PublishCommand` posts findings in a plain `for` loop with `try await` — one rejected
position throws and every later finding is never attempted.

**Cost.** Observed live on git.flat.lab (GitLab 19.5.3, MR !1336, 2026-11-20): C1/C2 posted,
N1's position was rejected, N2/N3 silently never ran — a partially published review that
only a re-run (the ledger makes it safe) repairs.

**Discharged.** Both publish passes isolate failures: pass 1 wraps `postDiscussion`,
pass 2 wraps `updateNote` — each prints `✗ <id> — <reason>` (`ErrorExplain`), the loop
continues, and the ledger records only successes. After the summary the command throws
`ValidationError` listing every failure, exiting non-zero; the message warns that a
failure throwing *after* GitLab committed can exist server-side unrecorded, so a re-run
is not guaranteed duplicate-free — check the MR first. Ledger writes stay outside the
`catch`: a failed save aborts rather than risking unrecorded threads.

### TD-7 — no context-line positions · discharged

`Position.lineType` models only `new` / `old` / `file` — `new_line` XOR `old_line`. A
`scope=line` anchor on an *unchanged* line inside a diff hunk (a context line, which
reviewers naturally pick) cannot be expressed; GitLab 19.5.3 answers `badRequest` to a
`new_line`-only position there.

**Cost.** Workaround is "anchor on `+` lines only" — now recorded in partner-ios's
CLAUDE.md — but the report format gives the author no warning at lint time.

**Discharged.** `publish --confirm` fetches the MR diffs (`mergeRequestDiffs`), parses
them into per-file new-side line maps (`DiffParser`), and resolves each anchor
(`AnchorResolver`): an added line posts `new_*` only, a context line posts `old_*` +
`new_*` together, and an anchor outside every hunk demotes to a general note with a
warning instead of a `badRequest`. Verified live on GitLab 19.5.3 (MR !1336,
2026-11-20): the both-sides position on a context line returns `201`.

### TD-8 — positions resolving to brace-only lines are rejected · discharged

`Finding.position` uses `lineEnd ?? lineStart` — the *end* of a `line=A-B` range. On
git.flat.lab (GitLab 19.5.3, MR !1336, 2026-11-20) a range ending on a bare `}` line
(`38-44` → `new_line=44`) got `400 {"line_code"=>["can't be blank", "must be a valid
line code"]}` while neighbouring added lines (`38`, `43`) posted fine.

**Cost.** Author must end ranges on the last meaningful line, not the closing brace —
recorded in partner-ios's CLAUDE.md; nothing warns at lint time.

**Discharged — misdiagnosis.** Probing MR !1336 on 2026-11-21 showed the rejection was
never about braces: added `}`/`    }`/`)` lines and context `}` lines all post `201`
when the coordinates are right. The `line_code can't be blank` error fires when the
position's coordinates don't identify a diff line — the original failure was a
*context* line sent `new_line`-only by the pre-TD-7 code, and a wrong `old_line` pair
reproduces the identical error today. TD-7's both-sides resolution already fixed the
real cause; no brace handling was ever needed.

### TD-9 — out-of-hunk anchors demote even where GitLab might accept them · discharged

`AnchorResolver` only knows lines inside diff hunks. GitLab 19.5 can anchor
unchanged lines *outside* the shown hunks when the position carries both
coordinates (Devin Review, PR #4) — but producing those coordinates needs the
whole-file old↔new line correspondence, which `…/diffs` doesn't provide.

**Cost.** A reviewer anchoring far from any change gets a general note instead
of a line note. Rare — the rubric already says anchor inside the diff.

**Discharged.** No file fetches needed: hunk headers already encode the
correspondence — every line outside hunks is unchanged, and unchanged regions
between/around hunks share a constant offset. `DiffParser` now records each
hunk's covered ranges (`DiffHunk`, count-0 aware) plus the file's
`new_file`/`deleted_file`/`collapsed`/`too_large` flags; `FileLineMap` maps an
out-of-hunk line to its other side and `AnchorResolver` emits the both-sides
position. Verified live on GitLab 19.5.3 (MR !1336, 2026-11-21): positions before
the first hunk (`100↔100`) and after it (`160↔157`, offset +3) both return `201`.
Added/deleted files, `too_large` diffs (possibly truncated), and empty diffs
still demote — no trustworthy correspondence exists there. `collapsed` diffs
still map: it's a UI fold, the diff text stays complete.

## See Also

- <doc:Design>
- <doc:Roadmap>
