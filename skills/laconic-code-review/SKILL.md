---
name: laconic-code-review
description: Conduct a thorough code review of changes on the current git branch against a base branch (default `develop`). Use whenever the user asks for "ревью этой ветки", "посмотри ветку", "review the branch", "code review", "second opinion on the diff", "check the MR", asks to compare new commits against a previous review, or asks to grade or critique a series of recent commits. Produces ONE human-editable Markdown report at `.claude/reviews/<branch>/<N>.md` whose machine fields live in HTML-comment anchors — validated by `laconic-review lint` and publishable to a GitLab merge request by `laconic-review publish`. Always invoke this skill for ANY review-style request — even if phrased informally as "что думаешь про эту ветку" or just a pasted diff. Do not improvise the review format; follow the rubric and emit the anchored format shown in the example.
---

# Code review — laconic

Produce a senior-engineer review of the current branch's changes versus base. The output is a **single artifact**:

- **`.claude/reviews/<branch>/<N>.md`** — a human-editable Markdown report whose machine fields live in HTML-comment anchors (`<!-- review … -->`, `<!-- finding … -->`). The user reads and edits it, then publishes it to the merge request with `laconic-review publish` (line-anchored + general discussions, idempotent). There is **no separate JSON** — the anchors carry every machine field the publisher needs; the prose is the comment body, posted verbatim.

`<N>` is the iteration counter — re-reviews of the same branch get `2.md`, `3.md`, … so the trail is preserved.

> **Prerequisite.** This skill shells out to the `laconic-review` CLI (from the laconic-review package) for the GitLab-facing steps — resolving the MR, validating, publishing. It must be on `PATH`. Everything this skill does itself is provider-neutral; GitLab lives entirely behind that CLI.

## When to trigger

Any review-style request. Examples that MUST invoke this skill:
- "Сделай ревью этой ветки."
- "Review the branch before merge."
- "Compare new commits against your previous review."
- "Check what changed since the last MR comment."
- "Second opinion on this diff."
- "Что думаешь про эти коммиты?"
- "Look at the MR — anything bad?"
- After the user pastes a diff or `git log` excerpt and asks for opinions.

If the request is ambiguous ("посмотри это" with no clear target), confirm: "Review of current branch against `develop`?" — then proceed.

## Flow

Follow these steps in order. Don't skip steps to "save time" — the trail and the `lint` self-check are what make the report publishable.

### 1. Detect git context (plain git)

```bash
git rev-parse --abbrev-ref HEAD                            # branch
git rev-parse develop 2>/dev/null || git rev-parse main 2>/dev/null || git rev-parse master  # base
git log --oneline <base>..HEAD                             # commits on the branch
git diff --stat <base>...HEAD                              # change shape
```

This is provider-neutral — no GitLab here. The project and remote are inferred by the CLI in step 2.

### 2. Resolve the target MR — and confirm if state is ambiguous

Delegate MR resolution to the connector (it owns GitLab — project path, encoding, API):

```bash
laconic-review resolve "<branch>" --base "<base>" --json
```

It returns the `iid` of the single open MR for the branch, or the candidate MRs otherwise. Apply this decision tree:

| Situation | Action |
|---|---|
| Current branch is `develop` / `main` / `master` | **Confirm with the user.** It's a base branch — ask whether to review a specific open MR or do a "what's new on `develop`" pre-MR review. |
| Exactly one open MR for this branch | Use its `iid`. Proceed silently. |
| Multiple open MRs for this branch | Pick the most recently updated; note in the report's TL;DR which one. |
| Only merged/closed MRs | **Confirm with the user.** Reviewing a merged conversation is rarely the intent — ask, or proceed as a pre-MR review. |
| No MR of any state | Proceed as a pre-MR review: `iid=0` in the anchor. |
| User named an MR explicitly ("review MR 967") | Use it directly; skip resolution. |

This matches the user's preference: don't waste a review pass on a merged conversation by accident.

### 3. Pick the iteration number

```bash
ls .claude/reviews/<branch-with-slashes>/ 2>/dev/null
```

Take the highest existing `<N>.md` and add one. Keep the branch's slashes (`fix/logout-sometimes/FPM-1653`) so the directory mirrors the issue structure.

### 4. Read the diff and key files

`git diff <base>...HEAD` (full unified diff). Then targeted `Read` on the files where issues likely live — don't reason from the diff alone; open the files for surrounding context.

### 5. Delegate to specialist skills

If the diff touches any of these areas, **read the corresponding skill before forming your opinion.** Don't reason about specialist domains from scratch.

| Diff content | Skill to read |
|---|---|
| `async`/`await`, `actor`, `@MainActor`, `Sendable`, `Task`, data races | `swift-concurrency` |
| SwiftUI views, state management, `@State`/`@Binding`/`@StateObject`, Liquid Glass | `swiftui-expert-skill` |
| Architecture decisions, MVC/MVVM, naming, SOLID, mocking, controllers vs views | `swiftui-foundations` |
| Deprecated SwiftUI APIs in the diff | `update-swiftui-apis` |
| Core Data — fetch requests, contexts, threading, migrations | `core-data-expert` |
| Tests — `#expect`, `#require`, traits, parameterized tests | `swift-testing-expert` |
| `Package.swift`, SPM plugins, `binaryTarget`, package resources | `swift-package-manager` |
| `.xcframework`, signing, distribution, C/C++ wrapping | `xcframework-distribution` |
| Apple API reference, HIG, WWDC details | `sosumi` |

The list isn't exhaustive — follow normal skill-discovery cues.

### 6. Write the report

Read `references/rubric.md` for the *content* rules: severity scale (🔴/🟡/🟢), status axis (⏳/🛠️/✅/❓), the `Nit:` rule, scope, cross-links, source citations.

The *form* (HTML anchors + layout) is owned by the laconic-review package, not this skill. **Emit by the golden example** `references/example-report.md`; the authoritative field set is the package's `Docs/report-format.md` and the `LaconicReviewCore` DocC. Don't restate the anchor schema in your prose — it drifts. In brief, a report is:

1. **One `<!-- review branch=… base=… iid=… iteration=<N> skill=laconic-code-review@1 -->` anchor.** All values are space-free.
2. **Human front-matter** — title, a one-paragraph TL;DR, the summary table, the merge recommendation. Everything before the first finding is for humans; the parser ignores it. **Group and summarize here.**
3. **Findings, back-to-back** — each a `<!-- finding id=… severity=… status=… scope=… [file=… line=… line_type=…] [links=…] -->` anchor immediately followed by its prose (the `### 🟡 C1. … — ⏳ Open` heading mirror, body, inline sources, code fences). Prose is published **verbatim**, so each block must read standalone.

**Hard rules** (the parser enforces them; violating them corrupts published comments):
- **No `##` section headers between findings, and nothing after the last one** — a finding's prose runs to the next anchor, so any such content leaks into the preceding comment. Use the front-matter for grouping.
- **`scope=line` needs `file` + `line`** (and the file/line must fall inside the diff range, or GitLab rejects the position).
- **Ids follow the severity mnemonic** B/C/N (a general-scoped concern is still `C`, never `G`); `severity=` is authoritative.
- **Cross-links** are `links=C2` (finding ids), not Markdown anchors. `laconic-review publish` rewrites them to thread URLs.

Russian prose by default for this project (see CLAUDE.md). Code identifiers, file paths, symbol names, log strings — **always English**, even in Russian prose (the `feedback_string_language_boundaries` rule: Cyrillic in logs/CI/asserts risks mojibake).

### 7. Validate once — don't loop

Aim to emit a correct report **by construction** (follow the example). Then validate with a **single** offline pass — and note that `laconic-review publish` (dry-run) already parses the report, so the dry-run the user runs before publishing doubles as a structural check:

```bash
laconic-review lint .claude/reviews/<branch>/<N>.md   # or rely on the publish dry-run's parse
```

`lint` adds the semantic checks beyond parsing (severity/status vocab, dangling `links=`, leaked `##`). Run it **once**; enter a fix-and-recheck loop **only if** it (or the dry-run) reports an error, or if the user explicitly asks — don't re-run it speculatively each turn. Then manually confirm the two things tooling can't: every line-anchored finding points inside the diff range, and every platform-behavior claim cites a source.

### 8. Ensure the report directory is ignored (honor global gitignore)

Check with `git check-ignore -q .claude/reviews/` — it honors the user's **global** `core.excludesfile`, nested rules, and the project `.gitignore` alike. If it's already ignored (exit 0), do nothing. Only if it is *not* ignored anywhere, mention it and prefer adding `.claude/reviews/` to the user's **global** ignore if they keep one — don't edit the project `.gitignore` unprompted.

### 9. Tell the user

End the turn with:
- the path to the report;
- a one-sentence summary: "Found 2 🔴 / 3 🟡 / 1 🟢; recommend not merging until B1 is fixed.";
- how to publish: `laconic-review publish .claude/reviews/<branch>/<N>.md` (dry-run) → add `--confirm` to post.

Nothing else — the report is the deliverable; don't restate it inline.

## Iterations (re-reviews)

When the user asks "что изменилось с прошлого ревью" or "compare to your last review", load the previous iteration's **`<N-1>.md`** (its anchors carry the findings — there's no JSON to read) and produce a new iteration that:

- **Carries ids forward.** A finding fixed since the last pass keeps its id (e.g., `B1`) with `status=closed`.
- **Adds new ids for new findings** — next free number in the severity category; never recycle a closed id.
- **Closed-with-nuance:** if a finding closes but introduces a new concern, open a **new** finding (next free id) and put `links=` on both, rather than reopening the old one.
- **Emits closed findings back-to-back like any other** — `status=closed`, prose citing the fix commit + a one-line verification. There is **no `## ✅ Исправлено` section** (it would leak); the front-matter summary table is where the reader sees what's closed vs open.

Only `status=open` findings publish. The user resolves a fixed thread with `laconic-review resolve-thread`.

## Language

Derive the **output language** in this priority order — first match wins:

1. The user's **explicit** request (e.g. "review in English", `lang=en`).
2. The **language of the user's prompt** for this review.
3. The **MR/PR description**.
4. The **code comments** in the diff.

It's no longer hard-coded (for the Флат project this resolves to Russian). Use one language consistently across the whole report.

**English regardless of the output language:**
- Code identifiers, file paths, symbol names, log strings, commit-message hints — **always**. (The `feedback_string_language_boundaries` rule: Cyrillic in logs/CI/asserts risks mojibake.)
- Established CS-principle abbreviations: DRY, KISS, SSOT, YAGNI, SOLID, APO, …
- An English term **only when it is more monosemic** than the output-language word; otherwise use the output language. So in Russian prose write «усиливает C2», not "Related: C2".

Cross-references in prose follow the output language; the machine link lives in the anchor's `links=`, and `publish` renders the footer language-neutrally (`🔗`).

## Sources to cite

When making a claim about platform behavior, cite one of these (Markdown link, inline in the finding's prose):

- **Apple Developer Documentation** — `https://developer.apple.com/documentation/...`
- **Swift Evolution** — `https://github.com/swiftlang/swift-evolution/blob/main/proposals/NNNN-...md`
- **WWDC sessions** — `https://developer.apple.com/videos/play/wwdcYYYY/NNNNN`
- **Apple Improving App Responsiveness** — `https://developer.apple.com/documentation/xcode/improving-app-responsiveness`
- **Google eng-practices** — `https://google.github.io/eng-practices/review/`

For specialist-skill-backed claims (concurrency, SwiftUI, Core Data), cite the skill name + section.

## Boundaries

This skill **produces and validates** the report. It does **not** publish: posting discussions (`laconic-review publish --confirm`) and resolving threads (`laconic-review resolve-thread --confirm`) are the user's gated steps. The report is provider-neutral; the GitLab specifics live in the `laconic-review` CLI, so this skill fits a future GitHub seam unchanged.

## See also

- `references/rubric.md` — severity, status, ids, `Nit:` rule, scope, cross-links, sources
- `references/example-report.md` — the golden sample (FPM-1653); your emission target
- the laconic-review package — `Docs/report-format.md` + `LaconicReviewCore` DocC: the authoritative format and field set (`laconic-review lint` is its executable form)
- `evals/evals.json` — test prompts for verifying the skill
