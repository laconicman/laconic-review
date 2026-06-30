# Rubric — review content rules

> **Structure (read efficiently).** The rules below are **language-neutral** — read them whatever
> the review's output language. Prose *examples* that depend on that language live in the
> **Phrasing examples** section at the end, split by language; read only the one matching your
> output language (see the skill's *Language* step) and skip the rest. These rules are the
> content contract; the *form* (HTML anchors + layout) is owned by the laconic-review package —
> emit by `references/example-report.md`, don't restate it here.

## Severity — three values

| Emoji | Meaning | Merge gate |
|---|---|---|
| 🔴 | **Blocker** — bug, data loss, regression, security, leak | Must be fixed before merge |
| 🟡 | **Concern** — design smell, fragile pattern, missing test, dead code | Should fix; merge only with explicit acknowledgement |
| 🟢 | **Nit** — style, cosmetics, readability. The body **begins with `Nit:`** | Author's discretion |

Severity emoji are **never reused** for any other meaning (status, importance, sections) — take
those from the status table or use other symbols. The `Nit:` convention is from
[Google eng-practices](https://google.github.io/eng-practices/review/reviewer/looking-for.html):
the prefix makes explicit that a remark is optional, so the author can skip it without friction.

## Status — a separate axis from severity

| Emoji | Meaning | Anchor token |
|---|---|---|
| ⏳ | Open — raised, not addressed | `open` |
| 🛠️ | In progress — author has taken it up | `in_progress` |
| ✅ | Closed — fixed and verified | `closed` |
| ❓ | Needs info — needs clarification from the author | `needs_info` |

The heading emoji is a human mirror; the machine reads the `status=` token. Only `open` findings
publish; `closed` closes the thread (`laconic-review resolve-thread`).

## Finding ids

A stable id `<prefix><n>`: `B1, B2, …` Blocker · `C1, C2, …` Concern · `N1, N2, …` Nit. The prefix
is a birth mnemonic; `severity=` is authoritative (it wins on conflict), so the id **never
changes** across iterations — that's the lineage key. There is **no letter for scope**: a
general-scoped concern is still `C<n>` with `scope=general`, never `G`. New findings take the next
free number in their category and never recycle a closed one.

## Scope

- **`line`** — anchored to a code fragment. Anchor carries `scope=line` + `file` + `line` (range
  `start-end` or one line) + `line_type` (`new`/`old`); publishes as a GitLab diff note. Never
  line-anchor a file **not in the MR diff** — GitLab rejects the position. `lint` checks
  `file`+`line`; SHAs aren't stored (publish fetches them fresh).
- **`general`** — architecture, missing tests, PR description, overall design. No file/line;
  publishes as a top-level MR note.

## Cross-references

If a finding relates to another in the same report, put the ids in the anchor: `links=C2`
(comma-separated, e.g. `links=C2,N1`) — finding ids, not GFM anchors. `laconic-review publish`
substitutes real thread URLs and renders the footer language-neutrally (`🔗`), so **never
hand-write a footer**. In prose, refer to the related finding in the output language (see
*Phrasing examples*).

## Sources

Any claim about Swift/runtime semantics, an Apple framework contract, Combine/async-await/actor
behaviour, or a best practice (Google, Apple HIG, RFC) must carry a source — a Markdown link,
**inline in the finding's prose** (the source travels with its comment, never a trailing table).
Minimum one source per claim; ideally the specific section/proposal with an anchor. For example:

> Actor-isolated functions are [reentrant](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md#actor-reentrancy):
> while suspended at an `await`, the actor may service other calls.

## Iterations

When asked to compare with a previous review, load the previous `<N-1>.md` (its anchors carry the
findings — there's no JSON):

1. For each prior finding: fixed → `status=closed`, id kept, cite the fix + a one-line
   verification; in progress / partial → `status=in_progress`; unchanged → `status=open`.
2. New findings → next free id in their category.
3. **Closed-with-nuance:** if closing a finding surfaces a new one, the old gets `status=closed`
   + `links=<new id>`, the new gets the next free id + `links=<old id>`; link both in prose.

Closed findings are emitted **back-to-back like any other** (`status=closed`) — never under a
`## …` section (it would leak into the preceding comment). The front-matter summary table is
where the reader sees closed vs open.

## What not to do

- Reuse 🔴/🟡/🟢 for anything but severity.
- Change a finding's id between iterations, or recycle a closed number.
- Encode scope in the id (there is no `G`; a general concern is `C<n>`).
- Put `##` section headers between findings, or anything after the last one (it leaks into a comment).
- Close a finding without citing the fix (code/commit).
- Line-anchor a file not in the diff.
- Make a platform/runtime claim without a source.
- Mix two languages in one phrase — except identifiers, file paths, symbol names, and code.

## Phrasing examples (read only your output language)

### English
- Nit body: `Nit: prefer guard here to cut the nesting.`
- Cross-reference: "reinforces C2", "closed with a caveat — see C5", "grows out of B1".

### Русский
- Тело nit'а: `Nit: лучше guard, чтобы убрать вложенность.`
- Перекрёстная ссылка: «усиливает C2», «закрыто с нюансом, см. C5», «прорастает из B1».
