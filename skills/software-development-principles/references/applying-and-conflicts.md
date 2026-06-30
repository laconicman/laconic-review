# Applying the principles — interactions, conflicts, counterpoints

The principles routinely pull against each other. This file is the reasoning layer: how the
clusters relate, how to resolve clashes, respected critiques that keep you from
cargo-culting, and a smell → principle lookup.

## Table of contents
- [The four clusters and how they relate](#the-four-clusters-and-how-they-relate)
- [Conflict-resolution order](#conflict-resolution-order)
- [DRY vs coupling — the wrong abstraction](#dry-vs-coupling--the-wrong-abstraction)
- [YAGNI vs code health](#yagni-vs-code-health)
- [APO vs the critical 3%](#apo-vs-the-critical-3)
- [BDUF vs emergent design](#bduf-vs-emergent-design)
- [Counterpoints — don't cargo-cult](#counterpoints--dont-cargo-cult)
- [Smell to principle lookup](#smell-to-principle-lookup)

## The four clusters and how they relate
The source deck groups the principles, and the grouping has real backing:
- **KISS + YAGNI + Occam** — keep the solution minimal and free of speculative or
  unjustified entities. These are the *default* posture and the tie-breakers.
- **DRY + SSOT** — keep each piece of knowledge in one authoritative place so logic is not
  smeared across the codebase.
- **SOLID + low coupling + high cohesion** — manage dependencies so the system stays
  changeable. (Martin: SOLID exists for dependency management; Constantine: high cohesion
  tends to produce low coupling. These are the same concern at different zoom levels.)
- **APO + Occam** — do not add complexity (including performance complexity) without a
  confirmed need.

A useful mental model: cohesion/coupling decide **where boundaries go**; SOLID gives
**named tactics** for those boundaries; KISS/YAGNI/Occam decide **how much structure** to
build; DRY/SSOT decide **where truth lives**; APO decides **when to spend on speed**; BDUF
decides **how much to think first**.

## Conflict-resolution order
A heuristic ordering — earlier usually outranks later when they collide. (Same flow as
SKILL.md, with the reasoning.)

1. **Correctness & clarity.** Nothing else matters if it is wrong or unreadable. Clarity is
   the Swift API Design Guidelines' explicit top priority.
2. **Cohesion / coupling (right boundaries).** Decide what belongs together and what should
   stay independent before writing code. A wrong boundary is the most expensive mistake to
   unwind.
3. **KISS + Occam (simplest sufficient).** Among workable designs, fewest moving parts.
4. **YAGNI (no speculation).** Don't build presumptive features or abstractions; add them
   when a real second case appears (Rule of Three). Keep code malleable regardless.
5. **DRY/SSOT — but subordinate to coupling.** Unify duplicated *knowledge* only when it
   does not force unrelated callers to couple through one abstraction. If it would, prefer
   the duplication.
6. **SOLID as dependency hygiene, where it pays.** Especially DIP for testable seams. Skip
   SOLID moves that add ceremony without lowering real change-cost.
7. **APO (measured performance only).** Optimize the profiled hot path; leave cold paths
   simple.
8. **BDUF proportional to cost of change.** Most for irreversible decisions, least for
   easily-changed internals.

## DRY vs coupling — the wrong abstraction
The most important conflict to internalize, because over-applying DRY is so common.

- **Sandi Metz, "The Wrong Abstraction" (2016):** *"Duplication is far cheaper than the
  wrong abstraction."* When an abstraction has to grow conditionals/parameters to serve
  callers whose needs are diverging, it has become a liability. Her prescription, verbatim:
  re-introduce duplication by **inlining the abstracted code back into every caller**,
  remove the abstraction and its conditionals, then let the now-visible duplication show you
  the *right* boundary. "When the abstraction is wrong, the fastest way forward is back. This
  is not retreat, it's advance in a better direction."
- **The DRY caveat that prevents this:** DRY is about *knowledge*, not text. Code that looks
  similar but encodes *different decisions* is not duplicated knowledge — unifying it couples
  things that should change independently.
- **Fowler's Rule of Three:** don't extract on the second occurrence; wait for the third.
  Premature extraction guesses at a shape you cannot yet see.
- **Net rule:** when DRY and low coupling conflict, low coupling usually wins. A little
  duplication is reversible; a wrong abstraction metastasizes.
- Fetch: https://sandimetz.com/blog/2016/1/20/the-wrong-abstraction

## YAGNI vs code health
YAGNI says skip the speculative feature; it does **not** say skip the refactor.
- Fowler: "Yagni is not a justification for neglecting the health of your code base. Yagni
  requires (and enables) malleable code." And: YAGNI applies to *capabilities built to
  support a presumptive feature*, not to effort that makes the software easier to modify.
- So: don't build the configurable plugin system nobody asked for (YAGNI), but do keep
  naming clear, tests present, and seams clean so the system *can* absorb that system later
  cheaply.
- Fetch: https://martinfowler.com/bliki/Yagni.html

## APO vs the critical 3%
"Premature" is the load-bearing word, not "optimization."
- Knuth's full point: forget small efficiencies ~97% of the time, **but do not pass up the
  critical 3% — after profiling identifies it.** APO is an argument for *measuring first*,
  not for ignoring performance.
- Practical sequence on Apple platforms: confirm the cost exists (`measure {}`) → locate it
  (Instruments Time Profiler / Allocations) → optimize that path → compare before/after
  profiles. Optimizing by intuition usually misses the real bottleneck and adds complexity.
- Tension to hold honestly: aggressive abstraction (deep polymorphism, indirection) can have
  measurable cost on hot paths (see Muratori, below). On a *measured* hot path, performance
  can outrank a clean-code default — but that is the exception, justified by data, not the
  rule.

## BDUF vs emergent design
The deck frames BDUF positively; the literature usually frames it negatively. The synthesis:
- Fowler, "Is Design Dead?": combine planned and evolutionary design; "when in doubt err on
  the side of simplicity"; simplify the architecture as soon as a part stops paying its way.
- Operational rule: invest up-front design in proportion to **cost of change** and
  **irreversibility** — data model, module boundaries, public APIs get real thought;
  internals stay simple and evolve. That is BDUF and YAGNI working together rather than in
  opposition.
- Fetch: https://martinfowler.com/articles/designDead.html

## Counterpoints — don't cargo-cult
Include these to resist mechanical application. They are credible, non-hyped senior voices.

- **Dan North, "CUPID — for joyful coding":** argues *properties* (Composable,
  Unix-philosophy, Predictable, Idiomatic, Domain-based) beat *principles*, and that
  mechanically applying SRP — e.g. splitting strictly by layer — can **reduce cohesion** and
  raise cognitive load. Treat SOLID as a lens, not a checklist; if a "SOLID" change makes the
  code harder to follow with no real payoff, it is over-engineering.
  Fetch: https://dannorth.net/cupid-for-joyful-coding/
- **Casey Muratori, "Clean Code, Horrible Performance":** the Clean Code abstraction style
  (especially virtual dispatch / polymorphism) can carry significant performance cost.
  Relevant *as a domain counterpoint* on measured hot paths and to the APO discussion — not a
  general refutation of readable code.
  Fetch: https://se-radio.net/2023/08/se-radio-577-casey-muratori-on-clean-code-horrible-performance/
- **General caution:** enthusiastic SOLID/DRY applied to a legacy codebase often ends in a
  mess. New abstractions, protocols, and layers must each earn their keep (Occam). When in
  doubt, prefer the simpler, more duplicated, more direct version and let real needs justify
  structure.

## Smell to principle lookup
A fast triage table from symptom → likely principle(s) → move.

| Smell / symptom | Likely principle(s) | Typical move |
|---|---|---|
| One small change forces edits in many files ("shotgun surgery") | Low cohesion / high coupling | Re-draw boundaries; collect what changes together |
| A "God" type / massive `View.body` / `Manager` doing everything | SRP / high cohesion | Extract focused types & subviews |
| A shared helper sprouting boolean flags / `if kind == …` to serve diverging callers | Wrong abstraction (DRY over-applied) | Inline it back into callers (Metz); find the real shape |
| Same business *rule* implemented in two places, drifting | DRY / SSOT | Single authoritative implementation; derive elsewhere |
| Duplicated UI state copied into a child view that drifts | SSOT | One owner; pass `@Binding` / read the model |
| A protocol/generic/layer with exactly one conformer and no test double | YAGNI / Occam | Delete the abstraction; use the concrete type |
| High-level code `import`s a concrete framework (CoreBluetooth, CoreML, URLSession) directly and is untestable | DIP / low coupling | Depend on your own protocol; inject the implementation |
| Read-only client forced to know about write/delete | ISP | Split the protocol; compose with `&` |
| A subtype that breaks the base type's contract / needs `is`-checks to special-case it | LSP | Re-model as sibling types behind a protocol; prefer value types |
| Adding a feature means editing a `switch` in many places | OCP | Add a conforming type instead |
| Clever generic signature nobody can read at the call site | KISS / Occam / API clarity | Prefer the clear, specific signature |
| Code optimized by guesswork, now complex, with no measured win | APO | Revert; measure; optimize only the profiled hot path |
| Whole object passed where a caller needs one field | Stamp coupling (low coupling) | Pass the value the caller actually needs |
| Big design spec written for easily-changed internals | BDUF over-applied / YAGNI | Reserve up-front design for expensive-to-reverse decisions |
