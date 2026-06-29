# laconic-review

A small Swift CLI that reads — and (soon) publishes — code-review findings against a GitLab
merge request, over [GitLabKit](../GitLabKit). The companion review skill produces a markdown
report; this connector turns approved findings into MR discussions.

## Architecture (why it's shaped this way)

The **connector leads**. GitLabKit's typed API is the source of truth for *how* a finding
becomes a discussion/note/position; the skill adapts its output to this interface, never the
reverse. Consequences:

- **One GitLab-aware file** — `LaconicReviewCore/GitLabConnection.swift`. Everything else (the
  CLI, the resolver, the DTOs) is provider-neutral. A future GitHub means a second connection
  type, not a rewrite.
- **`LaconicReviewCore`'s DocC is the contract.** The skill reads its symbol graph to learn what
  to emit and self-heals when GitLabKit changes — cheaper and more precise than reading source.
  So the `///` comments there are the spec, kept accurate on purpose.
- **The markdown report is the human-editable SSOT** (see *Report format* below). Position
  SHAs are **not** persisted in it — they're fetched fresh from `diff-refs` at publish time.

```
laconic-review (executable, ArgumentParser)
        └── LaconicReviewCore (library, testable)
                ├── GitLabConnection   ← the only file that imports GitLabKit
                ├── MergeRequestResolver (pure decision tree)
                ├── ProjectContext / GitLabConfig
                └── Models (neutral DTOs)
```

## Build

This depends on the sibling `../GitLabKit`, which must be rebuilt first — this scaffold made
**two** changes to it (both in one regen):

1. `Client(token:serverURL:)` — lets us point at `http://git.flat.lab` (the `hostname:`
   convenience forces `https://`).
2. `getApiV4User` added to the `review` tier filter — so `whoami` (`GET /user`) is generated.

```bash
cd ../GitLabKit && swift build      # regenerates the client with the two changes
cd ../laconic-review && swift build
swift test                          # runs the resolver unit tests (no network)
```

> **Not yet compiled here.** GitLabKit is Darwin-only (OSLog), so this scaffold was written
> against GitLabKit's README/handoff examples, not a compiler. The likely first-build fixes are
> all inside `GitLabConnection.swift` (exact generated field names / enum cases) — that
> isolation is the point.

## Use

The token is read from the environment (`GITLAB_TOKEN` by default), never passed as a flag.
`--project` and `--base-url` default to your `origin` remote.

```bash
export GITLAB_TOKEN="glpat-…"

laconic-review whoami
laconic-review resolve fix/logout-sometimes/FPM-1653 --base develop
laconic-review diff-refs 965
laconic-review discussions 965
laconic-review whoami --json          # any command: machine-readable output

# Publish a review report's findings to the MR (dry-run, then for real):
laconic-review publish .claude/reviews/fix-logout/1.md            # offline dry-run — prints the plan
laconic-review publish .claude/reviews/fix-logout/1.md --confirm  # posts; records 1.published.json
laconic-review resolve-thread .claude/reviews/fix-logout/1.md C1 --confirm   # resolve a finding's thread
```

## Report format (the inviolable bits)

Prose is freely editable; machine fields ride in one HTML comment per finding that no editor
(human or tool) may alter:

```markdown
<!-- review branch=… base=develop iid=965 iteration=1 skill=laconic-review@1 -->
<!-- finding id=C1 severity=concern status=open scope=line file=path/to/File.swift line=18-22 line_type=new links=C3 -->
### 🟡 C1. Title — ⏳ Open
…freely-editable prose, code, suggested fix…
```

The comment is the machine source of truth (the heading emoji is a human mirror); `id` is
stable across iterations for lineage. SHAs are intentionally absent — `publish` fetches
`diff_refs` from the MR.

## Status

Phase 2.b. Read: `whoami`, `resolve`, `diff-refs`, `discussions`. Write (dry-run unless
`--confirm`): `publish` parses the markdown SSOT, fetches `diff_refs`, and posts line-anchored
+ general discussions idempotently (via `<N>.published.json`); `resolve-thread` resolves a
published finding's thread. Next: adapt the `code-review-flat` skill to emit the HTML-anchored
markdown and drop the parallel `findings.json`.
