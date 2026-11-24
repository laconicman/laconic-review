# laconic-review

A small Swift CLI that reads and publishes code-review findings against a GitLab merge
request or a GitHub pull request. The companion review skill (`skills/laconic-code-review/`)
produces a markdown report; this connector turns approved findings into discussions — the
forge is detected from `git remote`, with a `--host` override.

## Architecture (why it's shaped this way)

Commands depend on `any ReviewHost` — the provider-neutral seam in `LaconicReviewCore`.
Each forge's API lives in its own target, so provider dependencies never leak into the
core or into each other:

- **`GitLabConnection`** — GitLabKit's typed API is the source of truth for *how* a finding
  becomes a discussion/note/position.
- **`GitHubConnection`** — a hand-written URLSession REST+GraphQL client (~10 calls;
  GraphQL is unavoidable for review threads, replies, and resolve/unresolve).

`LaconicReviewCore`'s DocC is the contract. The skill reads its symbol graph to learn what
to emit and self-heals when the seam changes — cheaper and more precise than reading
source. So the `///` comments there are the spec, kept accurate on purpose.

- **The markdown report is the human-editable SSOT** (see *Report format* below). Position
  SHAs are **not** persisted in it — they're fetched fresh from `diff-refs` at publish time.

```
laconic-review (executable, ArgumentParser)
        └── any ReviewHost
                ├── LaconicReviewCore (library, testable)
                │       ├── ReviewHost + HostConfig/ProjectContext (remote → forge, token env)
                │       ├── MergeRequestResolver (pure decision tree)
                │       └── Models (neutral DTOs)
                ├── GitLabConnection (library — GitLabKit/OpenAPI deps)
                └── GitHubConnection (library — Foundation only)
```

## Build & install

Depends on the sibling `../swift-gitlab` for the GitLab connection (which carries two small
additions this package needs: `Client(token:serverURL:)` for `http://` hosts, and
`getApiV4User` in the `review` tier so `whoami` is generated). The GitHub connection needs
nothing beyond Foundation. Build the sibling first, then this package:

```bash
cd ../swift-gitlab && swift build      # regenerates the client
cd ../laconic-review && swift build
swift test                             # offline unit tests
```

To call the CLI from anywhere — and from the companion skill — build release and put it on
`PATH`:

```bash
swift build -c release
sudo ln -sf "$PWD/.build/release/laconic-review" /usr/local/bin/laconic-review
```

`/usr/local/bin` usually needs `sudo`; or symlink into a user-writable dir already on your
`PATH` (e.g. `~/bin`) without it. Install the companion **skill** separately — see
[`skills/README.md`](skills/README.md).

> Because the install is a symlink into `.build/release/`, **`swift build -c release` is the
> deploy step** — a debug build alone leaves the installed CLI stale. When in doubt,
> `laconic-review --version` tells you which build you're running.

## Use

The forge is detected from the `origin` remote's host — a `github` DNS label
(`github.com`, `github.company.com`), `ghe.*`, or `*.ghe.com` maps to GitHub;
everything else stays GitLab (self-managed included). `--host github|gitlab`
overrides detection, e.g. for an exotic GHES hostname.

The token is read from the environment — `GITLAB_TOKEN` or `GITHUB_TOKEN` by default,
`--token-env` overrides — never passed as a flag. When the variable is unset, a
`--token-keychain <service>` flag reads it instead from the default Keychain (a
generic-password item, e.g. `gitlab.flat.lab`). `--project` and `--base-url` default to
your `origin` remote.

```bash
export GITHUB_TOKEN="ghp_…"          # or GITLAB_TOKEN="glpat-…"
# …or skip the export entirely and keep the token in the Keychain:
#   security add-generic-password -a "$USER" -s gitlab.flat.lab -w

laconic-review whoami
laconic-review whoami --token-keychain gitlab.flat.lab
laconic-review resolve fix/logout-sometimes/FPM-1653 --base develop
laconic-review diff-refs 965         # or 42 on GitHub — iid is the MR/PR number either way
laconic-review discussions 965       # 120-char previews — quick scan
laconic-review fetch 965             # full threads → .claude/reviews/<branch>/inbox-965.md
laconic-review whoami --json         # any command: machine-readable output

# Publish a review report's findings (dry-run, then for real):
laconic-review publish .claude/reviews/fix-logout/1.md            # offline dry-run — prints the plan
laconic-review publish .claude/reviews/fix-logout/1.md --confirm  # posts; records 1.published.json
laconic-review resolve-thread .claude/reviews/fix-logout/1.md C1 --confirm   # resolve a finding's thread

# Inbound loop — the review *of* your branch: fetch → fix → reply → resolve:
laconic-review fetch 1263                                    # every thread, verbatim, anchored
laconic-review reply 1263 <discussion-id> --body "…"         # dry-run — prints the plan
laconic-review reply 1263 <discussion-id> --body "…" --resolve --confirm   # post + resolve
laconic-review reply 1263 <discussion-id> --body-file reply.md --confirm   # text from a file/stdin
```

`fetch` drops every non-system thread — full note bodies, authors, diff anchors — into
`inbox-<iid>.md` under the MR/PR's source branch, in the same anchored-comment format as
reports. `reply` is dry-run unless `--confirm`; name the fix commit in the body so the
asker can distinguish "claimed fixed" from "verified".

GitHub specifics, all behind the same commands: line findings post as review comments
(`path`+`line`+`side`), general findings as issue comments; review threads — their ids,
replies, and resolve/unresolve — go through GraphQL since REST has no thread concept.
Anchors outside the diff hunks can't be placed on GitHub at all, so they publish as
general notes (with the location spelled out in the body) rather than line comments.

## Report format (the inviolable bits)

Prose is freely editable; machine fields ride in one HTML comment per finding that no editor
(human or tool) may alter:

```markdown
<!-- review branch=… base=develop iid=965 iteration=1 skill=laconic-review@1 head_sha=… -->
<!-- finding id=C1 severity=concern status=open scope=line file=path/to/File.swift line=18-22 line_type=new links=C3 -->
### 🟡 C1. Title — ⏳ Open
…freely-editable prose, code, suggested fix…
```

The comment is the machine source of truth (the heading emoji is a human mirror); `id` is
stable across iterations for lineage. Position SHAs are intentionally absent — `publish`
fetches the anchor refs fresh. `head_sha` is the one stored SHA: the head commit the
review was written against, which publish compares to the current head before trusting
anchors outside the diff hunks.

## Companion skill

The CLI needs a skill that speaks its report format. [`skills/laconic-code-review/`](skills/laconic-code-review/)
is that companion — it reviews a branch and emits the anchored markdown above, then self-heals
via `lint`. It's provider-neutral (it shells out to `laconic-review`), kept in-repo so the two
evolve together. See [`skills/README.md`](skills/README.md) to install it (copy vs symlink) and
for the direction this points: `skills/<name>/SKILL.md` is already the layout a **Claude plugin**
expects — a future `.claude-plugin/plugin.json` makes this repo an installable plugin bundling
the skill and the CLI.

## Status

Phase 2.c. Read: `whoami`, `resolve`, `diff-refs`, `discussions` (previews), `fetch` (full
threads → anchored inbox file) — on GitLab MRs and GitHub PRs. Write (dry-run unless
`--confirm`): `publish` parses the markdown SSOT, fetches the anchor refs, and posts
line-anchored + general discussions idempotently (via `<N>.published.json`); `reply` posts
into an existing thread (`--resolve`/`--unresolve`); `resolve-thread` resolves a published
finding's thread; cross-links between findings resolve to thread URLs in a second pass.
The companion skill in `skills/` emits this format. Next: package the repo as a Claude
plugin (`.claude-plugin/plugin.json`).
