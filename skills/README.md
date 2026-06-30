# Skills

Two skills ship with this package:

- **[`laconic-code-review/`](laconic-code-review/)** — the CLI's companion: it reviews a branch's
  diff and emits the HTML-anchored markdown report that `laconic-review` parses, lints, and
  publishes. The package isn't much use without a skill that speaks its report format. It's
  provider-neutral (it shells out to `laconic-review` for everything GitLab), so it already fits
  a future GitHub seam.
- **[`software-development-principles/`](software-development-principles/)** — a self-contained
  design-principles skill (KISS, DRY/SSOT, SOLID, coupling/cohesion, …) that `laconic-code-review`
  **consults by default**: it grounds architecture findings and supplies precise, shared
  vocabulary. Install it alongside the review skill — the review skill flags you if it's missing.

## Prerequisite

The `laconic-review` CLI must be built and on your `PATH` — the skill calls
`laconic-review resolve` / `lint` / `publish`. See **Build & install** in the
[root README](../README.md).

## Install the skills — pick one

Install **both** the review skill and its `software-development-principles` companion the same way.

**Snapshot (what's checked in here).** Each skill is self-contained. Copy them into your Claude
skills directory:

```bash
cp -R skills/laconic-code-review             ~/.claude/skills/laconic-code-review
cp -R skills/software-development-principles  ~/.claude/skills/software-development-principles
```

Simple, but the copies drift from this repo over time.

**Repo as the source of truth (no drift).** Symlink instead, so edits live in one place — here:

```bash
ln -s "$PWD/skills/laconic-code-review"             ~/.claude/skills/laconic-code-review
ln -s "$PWD/skills/software-development-principles"  ~/.claude/skills/software-development-principles
```

## Where this is heading: a Claude plugin

`skills/<name>/SKILL.md` is already the layout a Claude plugin expects. Adding a
`.claude-plugin/plugin.json` manifest turns this repo into an installable plugin that bundles the
skill (and eventually the built CLI), replacing the copy/symlink above with a plugin install.

## Notes

- **Duplicated example.** `laconic-code-review/references/example-report.md` copies the package's
  [`../Samples/example-report.md`](../Samples/example-report.md). A skill — and a plugin — must be
  self-contained, so the duplication is deliberate; the `Samples/` copy is canonical. Keep them in
  sync, or dedupe once plugin packaging settles.
- **Bundled principles skill.** `software-development-principles/` is a vendored copy; if you also
  maintain it elsewhere, keep them in sync (same caveat).
