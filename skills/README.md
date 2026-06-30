# Companion skill: `laconic-code-review`

[`laconic-code-review/`](laconic-code-review/) is the CLI's companion skill: it reviews a
branch's diff and emits the HTML-anchored markdown report that `laconic-review` parses, lints,
and publishes. The package isn't much use without a skill that speaks its report format — this
is that skill, kept in-repo so the two evolve together. It's provider-neutral (it shells out to
`laconic-review` for everything GitLab), so it already fits a future GitHub seam.

## Prerequisite

The `laconic-review` CLI must be built and on your `PATH` — the skill calls
`laconic-review resolve` / `lint` / `publish`. See **Build & install** in the
[root README](../README.md).

## Install the skill — pick one

**Snapshot (what's checked in here).** Self-contained: `SKILL.md`, `references/`, `evals/`.
Copy it into your Claude skills directory:

```bash
cp -R skills/laconic-code-review ~/.claude/skills/laconic-code-review
```

Simple, but the copy drifts from this repo over time.

**Repo as the source of truth (no drift).** Symlink instead, so edits live in one place — here:

```bash
ln -s "$PWD/skills/laconic-code-review" ~/.claude/skills/laconic-code-review
```

## Where this is heading: a Claude plugin

`skills/<name>/SKILL.md` is already the layout a Claude plugin expects. Adding a
`.claude-plugin/plugin.json` manifest turns this repo into an installable plugin that bundles the
skill (and eventually the built CLI), replacing the copy/symlink above with a plugin install.

## Note: the duplicated example

`laconic-code-review/references/example-report.md` copies the package's
[`../Samples/example-report.md`](../Samples/example-report.md). A skill — and a plugin — must be
self-contained, so the duplication is deliberate; the `Samples/` copy is canonical. Keep them in
sync, or dedupe once plugin packaging settles.
