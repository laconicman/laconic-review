# Handoff — laconic-review + GitLabKit (pair with Claude Code)

**Date:** 2026-06-29
**From:** A Cowork session (Claude Opus 4.8) that **could not compile** — its sandbox is Linux and
GitLabKit is Darwin-only (OSLog). So the connector below was written against GitLabKit's
README/handoff examples, not a compiler.
**For:** A **Claude Code** session on the user's Mac, which *can* build and test directly. Tighten
the loop: `swift build` → fix → rerun. You are the one who closes the inference gaps left below.
**Projects (pair):** `~/Documents/Code/Network/GitLabKit` and `~/Documents/Code/Network/laconic-review`
(the latter has a `.package(path: "../GitLabKit")`).

---

## Goal

A Claude plugin = a review **skill** (`code-review-flat`) + a **connector** (`laconic-review`, a Swift
CLI over GitLabKit) that publishes approved findings to a GitLab MR as line-anchored + general
discussions, idempotently across review iterations.

## Architecture invariants (do not violate)

- **The connector leads.** GitLabKit's typed API is the source of truth for the *interaction
  standard* (how a finding becomes a discussion/note/position/resolution). The skill adapts its
  output to the connector — never the reverse.
- **One GitLab seam:** `Sources/FlatReviewCore/GitLabConnection.swift` is the **only** file that
  imports GitLabKit. The CLI, resolver, DTOs, and config are provider-neutral. A future GitHub is a
  second connection type, not a rewrite.
- **Markdown is the human-editable SSOT.** Machine fields ride in per-finding HTML comments (see
  README → *Report format*). Position SHAs are **not** persisted in the markdown — they're fetched
  fresh from `diff-refs` at publish (the server is the truth for `position`).
- **DocC is the self-heal contract.** The skill reads `FlatReviewCore`'s symbol graph to learn what
  to emit; keep the `///` comments accurate — they're the spec, not decoration.

## State now

- **GitLabKit** — builds. Two edits this session (one regen covers both):
  1. `Client(token:serverURL:)` init — reach HTTP-only / self-managed hosts (`hostname:` forces
     `https://`). See new TD note **#6** (init shapes — reconsider).
  2. `getApiV4User` added to the `review`-tier filter (`openapi-generator-config.yaml`) — for `whoami`.
- **laconic-review** — read-only scaffold (Phase 2.a). The **platform-version build error is fixed**
  (declared iOS/tvOS/watchOS minimums to match GitLabKit; macOS is the real target). `MergeRequestResolver`
  has offline unit tests.

## First task (ordered)

1. `cd ~/Documents/Code/Network/laconic-review && swift build && swift test`.
   The platform error is resolved; the **next** failures (if any) compile-time, all inside
   `GitLabConnection.swift` — the only un-compiled code.
2. **Verify-on-build checklist** (every item is in `GitLabConnection.swift`):
   - project-id: `.case1(project)` for the **MR** ops vs plain `String` for the **notes/discussions**
     ops (a real GitLab spec inconsistency, preserved by the generator). Confirm the generated enum
     case name — could be `.case1` or a named case.
   - field names on `APIEntitiesMergeRequest` / `APIEntitiesNote`: `webUrl`, `updatedAt`,
     `diffRefs?.{base,head,start}Sha`, `system`, `position`, `resolvable`, `resolved`, `body`.
   - `getApiV4User()` zero-arg call shape and the `.ok.body.json` throwing-getter access.
   - list/discussions responses decode as arrays (GitLabKit retypes these — should already work).
3. Smoke test: `flat-review whoami`; against the lab, `flat-review diff-refs 965` (MR 965 is merged —
   safe to read).

## Next phases

- **publish / resolve-thread** (Phase 2.b, behind `--confirm`): parse the markdown SSOT → in-memory
  `Finding` → fetch `diff_refs` → POST line discussions
  (`postApiV4ProjectsIdMergeRequestsNoteableIdDiscussions`, with `position`) + general notes;
  cross-link threads; idempotency via `<N>.published.json` (finding id → discussion_url).
  resolve-thread = `putApiV4ProjectsIdMergeRequestsNoteableIdDiscussionsDiscussionId` (`resolved=true`).
- **Skill adaptation** (`code-review-flat`): emit markdown-only with the HTML-comment anchors; drop the
  parallel `findings.json`; derive the field set from `FlatReviewCore`'s DocC. Decide the rename — it
  stays provider-neutral, so it needs no "Git" in the name.
- Extend `FlatReviewCore` DocC to cover the publish types as they land.

## Pointers

| What | Where |
|---|---|
| Connector | `~/Documents/Code/Network/laconic-review/` — README has the architecture + format spec |
| GitLab seam | `…/laconic-review/Sources/FlatReviewCore/GitLabConnection.swift` |
| GitLabKit | `~/Documents/Code/Network/GitLabKit/` — README, `.docc/TechDebt.md` (#1 arrays, #6 init shapes) |
| Review skill | `~/.agents/skills/code-review-flat/` (+ symlinks) |
| Sample artifacts | `partner-ios/.claude/reviews/**/1.md` + `1.findings.json` (the current dual-artifact format) |
| GitLab facts | memory `ref_gitlab_lab.md` |

## Lab facts (don't rediscover)

- `git.flat.lab` is **HTTP-only** (the `serverURL:` init exists for this). PAT in `~/.zshenv` as
  `GITLAB_TOKEN`, scope `api`, identity `p.bukhstab` (id 63), project `FP/partner-ios`.
- `diff_refs` from `GET /merge_requests/:iid` is the server-side truth for line `position` — it
  overrides any locally-computed SHAs at publish time.
- Drop discussion threads where every note is `system == true` (`'added 1 commit'`, etc.).
