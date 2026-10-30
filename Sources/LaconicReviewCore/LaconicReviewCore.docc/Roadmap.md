# Roadmap

What is built, what is next, and what is deliberately not being built.

## Overview

Priority-ordered. Rationale lives in <doc:Design>; costs and discharges in <doc:TechDebt>.

## Now — shipped

- **The markdown SSOT and its parser.** One human-editable report, machine fields in
  HTML-comment anchors, SHAs never persisted.
- **Idempotent publishing to GitLab**, with a ledger so re-runs are safe.
- **`lint`** — severity/status vocabulary, dangling cross-links, leaked `##`, and the
  id-prefix/severity birth rule.
- **Iterations** — ids carried forward, `status=closed` with a verification line.

## Next — adopt what Devin Review does well

Recorded 2026-09-20 from **92 findings observed directly** across five pull requests in
`laconicman/{YDelivery, YandexDeliveryExpress, telegram-kb, laconic-contributor-kit}`,
three of those rounds handled end to end. This is direction, not a contract change: none
of it is implemented, and each item says what it would cost.

### 1. A `kind` axis, separate from severity

Devin marks every finding with a machine-readable `kind` in an HTML comment, and the
visible marker encodes **kind × severity**. Observed across the 92:

| `kind` | Marker | Observed |
|---|---|---:|
| `bug`, high | 🔴 red circle | 15 |
| `bug`, medium | 🟡 yellow circle | 39 |
| `security` | 🟥 red square | 1 |
| `analysis`, investigate | 🔍 | 33 |
| `analysis`, informational | 📝 | 4 |

**Asked the reviewer directly, 2026-09-20, and the answer changes what to adopt.** Its
reply, in full effect:

- Security findings have two severities, **Critical** and **Warning**. The public docs
  describe **red and orange shield icons** — not a guaranteed 🟥/🟨 textual mapping.
- Analysis flags have two intents, **Investigate** and **Informational**. So 🔍 versus 📝
  is **intent and actionability, not severity**.
- The publicly documented top-level categories are **Bugs**, **Security** and **Flags**.
  Whether the embedded `kind` values are limited to `bug`/`security`/`analysis`, or are a
  stable external contract at all, it would not confirm.
- Its closing caution: *the exact emoji and metadata values should not be treated as a
  supported API without confirmation from the Devin Review team.*

**So adopt the taxonomy, not the encoding.** The concepts are documented and worth having:
a category axis (bug / security / flag), a severity within a category, and — for flags —
an **intent** axis where *investigate* and *informational* are genuinely different asks
rather than two severities. Our own markers, our own vocabulary, no coupling to an
undocumented encoding that can change without notice.

That also settles the 🟨 question the observation could not: a Warning-severity security
finding **exists as a concept**, so the axis needs the level. What it looks like in our
reports is ours to choose.

**Why this matters here.** `severity` is the only axis this format has, and the rubric
forbids reusing its emoji. A finding that says *"this environment lacks `swift`, so I
could not run the suite — confirm the offline coverage in CI"* is not a blocker, not a
concern and not a nit. It is an **investigate** flag, and today it has to be mis-rated to
be filed at all. Of 25 findings handled across three rounds, **three** were this shape.

**Cost.** A new anchor field, `lint` vocabulary, `Docs/report-format.md`, the rubric, the
golden sample, and the vendored skill copy. Reports written by an older CLI must stay
readable — new fields decode as absent, never required.

### 2. `outdated` marks on superseded iterations

When Devin re-reviews, it **prepends a retraction to its own previous report body**:

```
> [!NOTE]
> **This report is out of date.** Scroll down for Devin Review's latest report on this PR.
```

Iterations here carry ids forward, but a reader landing on iteration 2's published thread
has no signal that iteration 3 exists. The reader most likely to land there is the author,
mid-round.

**Cost.** An edit to an already-published discussion, so `publish` would need to record
enough to find it — the ledger already does — plus a rule for what happens when the thread
was resolved in between.

### 3. Progressive disclosure in a finding

Devin's findings are a one-line title, a one-sentence claim, then a collapsed
`<details>` block carrying the mechanism, a worked **Example:** with named inputs, and a
**Recommended fix:**. The summary reads in seconds; the detail is one click away.

The rubric here asks for *why it matters* but leaves the shape open, so findings vary in
length and a long one buries its own claim.

### 4. A concrete failure case per finding, mandated

Every one of the 92 carried a named example — *"`main` and `feature` diverge at commit A,
then `main` adds M while `feature` adds F; `main...feature` must measure A to F, the code
measures M to F"*. That is what made all 25 checkable without running anything, and what
made a false positive impossible to hide.

This one needs **no contract change** — it is a rubric rule.

### 5. Suggestion blocks for one-line fixes

Where the fix is a single line, Devin emits a fenced ` ```suggestion ` block the platform
renders as appliable. One of the 25 arrived that way and was applied verbatim.

GitLab supports the same syntax, so this is a rubric rule plus a note in the publish path.

### 6. A resolution reply that names the fix

Devin replies in-thread with `✅ **Resolved**: <what changed>` rather than only flipping a
state. That reply is what lets a contributor-side tool distinguish *the asker confirmed
this* from *I claimed I fixed it* — see the companion `contributions` skill, which depends
on exactly this signal.

`resolve-thread` flips resolution without prose today.

## Later

- A second connection type for GitHub, as <doc:Design> anticipates. Devin's conventions
  are GitHub-shaped; adopting them is easier if both providers exist.

## Not being built

- A severity level between blocker and concern. No finding in the 92 needed one, and a
  fourth level changes the merge-gate table and every id prefix. Revisit only with a real
  finding that fits neither.

## See Also

- <doc:Design>
- <doc:TechDebt>
