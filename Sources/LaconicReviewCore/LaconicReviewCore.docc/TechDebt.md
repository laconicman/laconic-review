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
reports stay readable.

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

## See Also

- <doc:Design>
- <doc:Roadmap>
