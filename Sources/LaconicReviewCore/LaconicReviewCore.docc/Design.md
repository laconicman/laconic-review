# Design

The decisions this package rests on, why each was taken, and what was rejected.

## Overview

Authoritative over code comments where they disagree.

## The markdown report is the source of truth

One human-editable file per iteration. Machine fields ride in `<!-- review … -->` and
`<!-- finding … -->` HTML comments beside the prose they describe.

**Rejected:** a parallel `.findings.json` alongside heading-anchored markdown — the shape
the retired `code-review-flat` skill used. Two files drift, and the one a human edits is
the one that wins in practice, so the machine half was always the stale one.

**Rejected equally:** parsing the prose. A report is written to be read by a person; any
parser aimed at prose is permanently fragile, and the format has to stay human-editable.

## Severity and status are separate axes

`severity` (blocker / concern / nit) answers *how bad*; `status` (open / in_progress /
closed / needs_info) answers *where it stands*. Conflating them means a fixed blocker has
nowhere to go but deletion, and deletion loses the lineage.

The heading emoji mirrors severity for humans; the machine reads the anchor. **Severity
emoji are never reused for anything else** — a reader who sees 🔴 must never have to ask
whether it means a blocker or an in-progress marker.

<doc:Roadmap> proposes a third axis, `kind`, for the same reason the first two are
separate: a request to verify something is not a severity rating.

## Ids are the lineage key

`B1`, `C2`, `N3` — stable across iterations, never recycled. At birth the prefix must
agree with `severity=`; re-rating a finding while drafting means renumbering it.

**Why birth-time rather than always:** a finding legitimately re-rated in a later
iteration keeps its original prefix, because the id is the lineage and changing it would
break the link to the published thread. `severity=` stays authoritative; `lint` warns and
that one case is the expected warning.

## Only `open` findings publish

A closed finding still appears in the report — that is how the author sees what was fixed
— but publishing it would post a comment about something already resolved.

## Position SHAs are never persisted — but the reviewed head is

`publish` fetches `diff_refs` fresh and combines them with a ``Position`` at post time: a
position built from a stored SHA would be wrong the moment the branch moves. The one
exception is `head_sha` in the review anchor — not a position input, but a *revision
stamp*: publish compares it to the current head and refuses out-of-hunk anchor inference
when they differ, since bare line numbers can't be trusted across a push (TD-10).

## Only one type knows GitLab

Review intelligence and the report format are provider-neutral; ``GitLabConnection`` holds
every GitLab call. A second provider is a second connection type, not a rewrite.

## Publishing is idempotent

``PublishLedger`` records what was posted, so a re-run posts nothing twice. A review tool
that double-posts on a retry trains its readers to ignore it.

## See Also

- <doc:Roadmap>
- <doc:TechDebt>
