---
name: software-development-principles
description: >-
  Core software-design principles as decision aids and shared vocabulary for Swift and
  Apple-platform work: KISS, DRY (single source of truth), YAGNI, BDUF (proportional
  up-front design), the five SOLID principles, low coupling, high cohesion, avoiding
  premature optimization (APO), and Occam's razor. Use this for essentially every coding
  task — writing, reviewing, refactoring, debugging, naming, or designing types, modules,
  protocols, and APIs — and especially whenever you must choose between two designs,
  justify a design choice, judge whether code is over- or under-engineered, or cite an
  authority (Robert C. Martin, Barbara Liskov, Donald Knuth, Larry Constantine, Hunt and
  Thomas, Martin Fowler, Sandi Metz). Also trigger on phrases like clean code, separation
  of concerns, dependency injection, single source of truth, coupling, cohesion,
  abstraction, premature optimization, or over-engineering, even when no principle is
  named. Pairs with the swiftui-foundations skill for SwiftUI architecture specifics.
---

# Software Development Principles

A small, deliberately basic set of general principles, treated as **decision aids and a
shared vocabulary** — not commandments. Their job is to help you choose between workable
designs, explain *why* a choice is reasonable, and notice when code is drifting toward
either under- or over-engineering. They are heuristics that frequently conflict; the
skill is mostly about resolving those conflicts sensibly and citing the right authority
when reasoning about a trade-off.

This is *not* a "write good code, make no mistakes" checklist. Applied mechanically these
principles produce worse code — that failure mode (cargo-culting) is covered explicitly in
`references/applying-and-conflicts.md`.

## How to use this skill

1. For routine coding, the **decision flow** and **principles at a glance** below are
   usually enough — apply them inline without fetching anything.
2. Fetch a reference file only when you need depth: a canonical definition, the exact
   wording of a principle, an idiomatic Swift example, a conflict resolution, or a source
   to cite. The router table says which file.
3. When you invoke a principle to justify a decision, **name the source** where it helps
   ("this is Liskov substitution", "Metz: duplication is cheaper than the wrong
   abstraction"). Attribution is welcome and lends weight even when the reasoning stands
   on its own. Full citations live in `references/sources.md`.

## Principles at a glance

Grouped by what they buy you. One line each; full treatment in `references/principles.md`.

**Keep it minimal**
- **KISS** (Keep It Simple, Stupid) — choose the solution that is just simple enough for
  the task; complexity should come from requirements, not from wanting to use a tool.
- **YAGNI** (You Aren't Gonna Need It) — build what the current requirement needs, not
  what you foresee. *But keep the code malleable* — YAGNI never excuses code that is hard
  to change (Fowler).

**One source of truth**
- **DRY** (Don't Repeat Yourself) — every piece of *knowledge* has one authoritative
  representation (Hunt & Thomas). It is about knowledge/intent, not merely repeated text.
- **SSOT** (Single Source of Truth) — the data/rule lives in one place and others derive
  from it. This is Apple's own framing for SwiftUI state.

**Manage dependencies & change**
- **SOLID** (Martin; acronym by Feathers): **S**RP one reason to change · **O**CP open for
  extension, closed for modification · **L**SP subtypes substitute for their base (Liskov)
  · **I**SP many small interfaces over one fat one · **D**IP depend on abstractions, not
  concretions.
- **Low coupling** — minimize how much modules must know about each other (Constantine).
- **High cohesion** — each module's parts genuinely belong together (Constantine). High
  cohesion tends to *produce* low coupling.

**Avoid unjustified complexity**
- **APO** (Avoid Premature Optimization) — optimize a *measured* bottleneck, not a guess
  (Knuth). The famous quote has a second half: don't pass up the critical 3% — *after*
  profiling identifies it.
- **Occam's razor** — among solutions that all work, prefer the one with the fewest
  assumptions and moving parts. A meta-principle / tie-breaker.

**Think before building**
- **BDUF** (Big Design Up Front) — here, framed *positively and proportionally*: think
  through the task, constraints, and the expensive-to-reverse decisions before coding.
  Scale the up-front design to the cost of change; balance against YAGNI (Fowler, "Is
  Design Dead?").

## Decision flow (heuristic, not rigid)

When designing, reviewing, or refactoring, walk roughly this order. Earlier steps usually
outrank later ones when they collide.

1. **Correct and clear first.** It must do the right thing and be readable. In Swift,
   "clarity is more important than brevity" (Swift API Design Guidelines).
2. **Right home?** Put each responsibility where it belongs — keep a type cohesive, keep
   types loosely coupled (separation of concerns). Ask "does this logic belong here?"
   before "how do I write it?"
3. **Simplest sufficient design** (KISS + Occam). Among designs that work, take the one
   with the fewest moving parts.
4. **No speculative generality** (YAGNI). Add an abstraction (a protocol, a generic, a
   layer) when a *real* second case or a test double exists — roughly the Rule of Three
   for extraction. Still, keep what you write easy to change.
5. **Remove duplicated *knowledge*** (DRY/SSOT) — **but only if it does not force
   unrelated callers to couple through one abstraction.** If a shared helper has sprouted
   boolean flags / conditionals to serve callers that are diverging, it is the *wrong*
   abstraction: inline it back and let the real shape re-emerge (Metz). Duplication is far
   cheaper than the wrong abstraction; low coupling usually wins this clash.
6. **Apply SOLID as dependency hygiene where it lowers real change-cost** — especially
   **DIP**: depend on protocols and inject dependencies, which gives you low coupling and
   testability. Do *not* split by layer for its own sake; that can lower cohesion and
   raise cognitive load (North / CUPID).
7. **Performance last, and only after measuring** (APO). Do not micro-optimize cold paths.
   Do profile (Instruments → Time Profiler), then optimize the measured-critical part.
8. **Up-front design proportional to cost of change** (BDUF). More for irreversible
   decisions (data model, module boundaries, public API); less for easily-changed
   internals.

## High-leverage tensions to remember

- **DRY vs coupling** — over-DRYing couples unrelated code. Prefer a little duplication
  over a premature shared abstraction (Metz; Fowler's Rule of Three).
- **YAGNI vs code health** — skip speculative *features*, but never skip making code
  malleable (Fowler). YAGNI applies to presumptive capabilities, not to refactoring.
- **APO vs the critical 3%** — "premature" is the operative word; Knuth still demands you
  optimize the hot path once it is *identified* by measurement.
- **SOLID is not dogma** — it serves change; if a "SOLID" move hurts readability or
  cohesion with no real payoff, it is over-engineering (North).

## Swift / Apple-platform mapping (brief)

Idioms and full code examples are in `references/swift-apple-idioms.md`.

- **SSOT** → SwiftUI data flow: `@State` (view-local truth), `@Binding` (a reference to
  truth owned elsewhere), `@Observable` + `@Bindable` (Observation, iOS 17+; older:
  `@StateObject` / `@ObservedObject`). Apple literally calls this "single source of truth."
- **DIP / low coupling** → protocols + initializer injection; SwiftUI `@Environment`
  injection; Point-Free's swift-dependencies for many controllable dependencies (Date,
  UUID, Clock). Protocol-oriented programming over class inheritance (WWDC 2015).
- **SRP / high cohesion** → SwiftUI view decomposition into small subviews; separating
  **domain logic** (entities, business rules → model types) from **application logic**
  (coordination, presentation state → controllers / view models), with views only
  rendering. The MV-vs-MVVM choice is a trade-off — see the idioms file. **For SwiftUI
  architecture depth, defer to the `swiftui-foundations` skill.**
- **OCP / ISP / LSP** → add a protocol conformer instead of editing a `switch`; split fat
  protocols and compose with `A & B`; prefer value types over deep inheritance.
- **APO** → measure with `XCTest`/Swift Testing `measure {}` and Instruments before
  optimizing.
- **Library vs roll-your-own** → itself a YAGNI/Occam/DRY call: reach for a vetted SPM
  (e.g. swift-algorithms, SwifterSwift) when the needed bit is bigger than a tiny snippet
  and the dependency earns its maintenance/coupling cost; otherwise inline a few lines.

## Reference router

| When you need… | Read |
|---|---|
| Canonical definition, originator, exact wording, why it matters, per-principle source | `references/principles.md` |
| Idiomatic Swift / Apple-platform code examples for each principle (SwiftUI SSOT, DI, framework wrapping, Core ML / Core Bluetooth seams, API-design clarity) | `references/swift-apple-idioms.md` |
| Prioritization order, principle conflicts, the "wrong abstraction" problem, anti-cargo-cult counterpoints (Metz, North, Muratori), code-smell → principle table | `references/applying-and-conflicts.md` |
| Full citations with stable fetch-on-demand URLs, plus citation-integrity caveats (who really coined what) | `references/sources.md` |

### Reference file summaries

- **`references/principles.md`** — All ten principles (the eight from the source deck plus
  low coupling and high cohesion), grouped by cluster. Per principle: short definition,
  originator + primary source, why it matters, a one-line Swift note, and inline fetch
  URLs. Includes the coupling/cohesion spectrum and accuracy caveats.
- **`references/swift-apple-idioms.md`** — Short, modern, commented Swift examples mapping
  each principle to Apple-platform practice, with citation comments. Leans on official
  Apple docs and WWDC first, then respected community sources.
- **`references/applying-and-conflicts.md`** — How the principles interact and how to
  resolve clashes; the cluster groupings; deep dives on DRY-vs-coupling, YAGNI-vs-health,
  APO-vs-critical-3%, BDUF-vs-emergent design; respected counterpoints; a smell→principle
  lookup.
- **`references/sources.md`** — Consolidated bibliography (author, title, year, DOI/edition)
  with stable URLs to fetch on demand, organized by principle, plus the misattribution
  caveats so citations stay honest.
