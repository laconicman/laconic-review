# Principles — definitions, originators, sources

Canonical reference for each principle. Per entry: a short definition, the originator and
primary source, why it matters, a one-line Swift note, and inline fetch-on-demand URLs.
Full bibliographic detail and misattribution caveats are in `sources.md`; idiomatic Swift
examples are in `swift-apple-idioms.md`.

Most of these are long-settled in the literature; where attribution is genuinely contested
or commonly mis-stated, it is flagged. Treat the **definitions** as authoritative and the
**Swift notes** as conceptual guidance to apply with judgment, not verbatim rules.

## Table of contents
- Keep it minimal: [KISS](#kiss), [YAGNI](#yagni)
- One source of truth: [DRY + SSOT](#dry--ssot)
- Manage dependencies & change: [SOLID overview](#solid-overview), [SRP](#srp), [OCP](#ocp), [LSP](#lsp), [ISP](#isp), [DIP](#dip), [Low coupling](#low-coupling), [High cohesion](#high-cohesion)
- Avoid unjustified complexity: [APO](#apo), [Occam's razor](#occams-razor)
- Think before building: [BDUF](#bduf)

---

## KISS
**Keep It Simple, Stupid.** Choose the solution that is just simple enough for the task.
Complexity should arise from the requirements, not from a wish to use a new tool or pattern.

- **Origin:** A design maxim, not a software paper. Widely attributed to Clarence "Kelly"
  Johnson (Lockheed Skunk Works, designers of the U-2 / SR-71) and noted as a U.S. Navy
  principle around 1960. Johnson's framing: a jet had to be repairable by an average
  mechanic in the field with basic tools. No founding book; it is design culture.
- **Why it matters:** Simple solutions are easier to read, safer to change, and cheaper to
  hand to a teammate. Simplicity is the cheapest form of maintainability.
- **Swift note:** Swift's own API Design Guidelines encode KISS — "Clarity is more
  important than brevity," and making the smallest possible code is a *non-goal*.
- **Fetch:** https://en.wikipedia.org/wiki/KISS_principle ·
  https://www.swift.org/documentation/api-design-guidelines/

## YAGNI
**You Aren't Gonna Need It.** Implement capabilities when the current requirement actually
needs them, not when you merely foresee needing them.

- **Origin:** An Extreme Programming practice (Kent Beck, *Extreme Programming Explained*,
  under "Simple Design"). The most-quoted one-liner — "Always implement things when you
  actually need them, never when you just foresee that you need them" — is **Ron Jeffries'**,
  popularized by **Martin Fowler's** essay "Yagni" (2015).
- **Critical nuance:** YAGNI applies to *presumptive features*, **not** to keeping code
  malleable. Fowler: "Yagni is not a justification for neglecting the health of your code
  base. Yagni requires (and enables) malleable code." It is only safe alongside good
  design, tests, and refactoring discipline (Jeffries).
- **Why it matters:** Speculative generality is a leading source of accidental complexity
  and dead code; you can always recover deleted code from version control.
- **Swift note:** Don't add a `protocol`, generic parameter, or "manager" layer until a
  second concrete conformer or a test double genuinely exists.
- **Fetch:** https://martinfowler.com/bliki/Yagni.html ·
  https://ronjeffries.com/articles/019-01ff/iter-yagni-skimp/

## DRY + SSOT
**DRY — Don't Repeat Yourself:** "Every piece of knowledge must have a single, unambiguous,
authoritative representation within a system." **SSOT — Single Source of Truth:** data or a
rule lives in exactly one place; everything else derives from it.

- **Origin:** Andy Hunt & Dave Thomas, *The Pragmatic Programmer* (1999; 20th-Anniversary
  ed. 2019), section "The Evils of Duplication," Tip 15.
- **Crucial caveat:** DRY is about **knowledge / intent**, not textual similarity. Two code
  fragments that merely *look* alike but encode *different* decisions are not a DRY
  violation, and unifying them couples unrelated things. (See the wrong-abstraction
  discussion in `applying-and-conflicts.md`.)
- **Why it matters:** Duplicated knowledge forces you to find and change every copy in lock
  step; misses cause bugs and drift. SSOT is the positive form: derive, don't copy.
- **Swift note:** Apple uses "single source of truth" as a core SwiftUI concept — `@State`
  owns local truth, `@Binding` references truth owned elsewhere, an `@Observable` model is
  shared truth. Hand-maintained parallel copies of state are the classic anti-pattern.
- **Fetch:** https://pragprog.com/tips/ ·
  https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app ·
  https://developer.apple.com/videos/play/wwdc2019/226/

---

## SOLID overview
Five object-oriented design principles assembled by **Robert C. Martin** ("Uncle Bob")
across ~1996 *C++ Report* articles and his 2000 paper "Design Principles and Design
Patterns"; the **SOLID acronym was coined ~2004 by Michael Feathers** (author of *Working
Effectively with Legacy Code*). Fullest book treatment: Martin, *Agile Software Development:
Principles, Patterns, and Practices* (Prentice Hall, 2002), later *Clean Architecture*
(2017). Note two are older than Martin's framing: OCP is Bertrand Meyer's (1988) and LSP is
Liskov's. Their shared purpose is **dependency management so code stays flexible, robust,
and reusable** — not ceremony for its own sake.

- **Fetch (Martin's original "Principles of OOD"):**
  http://butunclebob.com/ArticleS.UncleBob.PrinciplesOfOod ·
  https://en.wikipedia.org/wiki/SOLID

### SRP
**Single Responsibility Principle** — "A class should have one, and only one, reason to
change." Group what changes together; separate what changes for different reasons.
- **Swift note:** A SwiftUI view renders; a service does I/O; a model holds domain rules.
  Calling `URLSession` inside a `View.body` mixes two reasons to change.

### OCP
**Open–Closed Principle** (Meyer 1988; in Martin's set) — software entities should be "open
for extension, but closed for modification." Add new behavior by adding code, not by editing
working code.
- **Swift note:** Add a new type conforming to a `protocol` rather than adding a case to a
  `switch` scattered across the codebase. Protocol extensions provide default behavior.

### LSP
**Liskov Substitution Principle** — a subtype must be usable anywhere its base type is
expected **without breaking the program's expected behavior** (preconditions not
strengthened, postconditions not weakened, invariants preserved).
- **Origin:** Barbara Liskov, "Data Abstraction and Hierarchy," OOPSLA-87 keynote (SIGPLAN
  Notices 23(5), 1988); formalized as behavioral subtyping in Liskov & Jeannette Wing, "A
  Behavioral Notion of Subtyping" (ACM TOPLAS 16(6), 1994).
- **Swift note:** Prefer protocols + value types over deep class hierarchies; the classic
  Square-is-a-Rectangle violation simply does not arise when both are structs conforming to
  a `Shape` protocol. `final` classes also remove a class of LSP hazards.
- **Fetch:** https://en.wikipedia.org/wiki/Liskov_substitution_principle ·
  https://dl.acm.org/doi/10.1145/197320.197383

### ISP
**Interface Segregation Principle** — "Clients should not be forced to depend on interfaces
they do not use." Prefer several small, role-focused protocols to one fat one.
- **Swift note:** The standard library models this — `Equatable`, `Hashable`, `Comparable`
  are separate; compose with `A & B` when a client needs both. Split a fat `DataStore`
  protocol into `DataReading` and `DataWriting`.

### DIP
**Dependency Inversion Principle** — "High-level modules should not depend on low-level
modules; both should depend on abstractions. Abstractions should not depend on details;
details should depend on abstractions." This is the single best-supported SOLID principle in
idiomatic Swift.
- **Swift note:** A view model depends on a `WeatherService` *protocol*, not on `URLSession`
  or a concrete client; the concrete implementation is injected (initializer injection,
  SwiftUI `@Environment`, or swift-dependencies). This yields low coupling and testable code.
- **Fetch:** https://developer.apple.com/videos/play/wwdc2015/408/ (Protocol-Oriented
  Programming) · https://github.com/pointfreeco/swift-dependencies

### Low coupling
**Minimize how much one module must know about another** so a change in one rarely forces
changes in others.
- **Origin:** Larry Constantine (late 1960s), first published in Stevens, Myers &
  Constantine, "Structured Design" (*IBM Systems Journal*, 1974); book: Yourdon &
  Constantine, *Structured Design* (1979). The coupling spectrum (worst → best: content,
  common, control, stamp, data) is detailed by Meilir Page-Jones, *The Practical Guide to
  Structured Systems Design* (1980/1988). Framed as a design pattern in Craig Larman's
  GRASP (*Applying UML and Patterns*, 2004).
- **Swift note:** Value types (structs/enums copy rather than share), protocol seams, and
  dependency injection all lower coupling. Passing whole objects when a caller needs one
  field is *stamp coupling*; reaching into another type's internals is *content coupling*.
- **Fetch:** https://en.wikipedia.org/wiki/Coupling_(computer_programming) ·
  https://en.wikipedia.org/wiki/GRASP_(object-oriented_design)

### High cohesion
**Each module's elements genuinely belong together** and serve one clear purpose. The
strongest form is *functional* cohesion (everything contributes to a single well-defined
task); the weakest is *coincidental* (grouped for no real reason — e.g. a `Utils` dumping
ground).
- **Origin:** Same lineage as coupling (Constantine; Myers used "module strength"). Cohesion
  spectrum (worst → best: coincidental, logical, temporal, procedural, communicational,
  sequential, functional) from Page-Jones. Constantine's insight: **higher cohesion tends to
  produce lower coupling.**
- **Swift note:** Extract a focused subview/type when one accumulates unrelated
  responsibilities; resist `Helpers`/`Manager` catch-alls. Cohesion and coupling are two
  sides of "did I draw the boundary in the right place?"
- **Fetch:** https://en.wikipedia.org/wiki/Cohesion_(computer_science)

---

## APO
**Avoid Premature Optimization.** Optimize a *measured* performance problem, not a guessed
one. The complete, in-context quote matters:

> "We should forget about small efficiencies, say about 97% of the time: premature
> optimization is the root of all evil. **Yet we should not pass up our opportunities in
> that critical 3%.**" — Donald Knuth, "Structured Programming with go to Statements" (*ACM
> Computing Surveys* 6(4), 1974).

- **Caveat:** The second sentence is usually dropped. Knuth insists you *do* optimize the
  critical part — **after** profiling identifies it ("a good programmer ... will be wise to
  look carefully at the critical code; but only after that code has been identified"). He
  later called it "Hoare's Dictum"; Hoare suspected Dijkstra — so the attribution itself is
  uncertain.
- **Why it matters:** Optimizing before measuring usually adds complexity (hurting KISS and
  cohesion) with no measurable win, and often misses the real bottleneck.
- **Swift note:** Confirm a real cost first (`measure {}` in XCTest / Swift Testing), then
  find the hot path with Instruments (Time Profiler, Allocations). Apple's documented stance
  is measure-first: gather info → measure to find causes → change one thing → compare a
  before/after profile.
- **Fetch:** https://en.wikiquote.org/wiki/Donald_Knuth ·
  https://developer.apple.com/documentation/xcode/improving-your-app-s-performance

## Occam's razor
**Among competing solutions that all work, prefer the one requiring the fewest assumptions
and entities.** A meta-principle / tie-breaker rather than a code rule.

- **Origin & honesty caveat:** Attributed to the 14th-c. Franciscan William of Ockham, but
  the famous Latin "entia non sunt multiplicanda praeter necessitatem" **does not appear in
  his surviving works** — it was phrased by later authors, and the name "Occam's Razor" is
  19th-century. What Ockham actually wrote includes "Plurality must never be posited without
  necessity." Cite the sentiment to Ockham; do not attribute the Latin slogan to him.
- **Why it matters:** New layers, services, and abstractions must earn their keep; an extra
  entity with no clear benefit is the thing to cut. Closely allied to KISS and YAGNI.
- **Swift note:** If two designs satisfy the requirement and one adds a protocol, a
  coordinator, and a wrapper while the other is three functions, prefer the latter until a
  concrete need justifies the structure.
- **Fetch:** https://en.wikipedia.org/wiki/Occam%27s_razor

---

## BDUF
**Big Design Up Front.** In the source deck (and here) this is framed **positively and
proportionally**: before implementing, think through the task, its constraints, and the main
architectural decisions; discuss contentious or expensive choices early so there is less
rework later.

- **Important context:** In Agile/XP literature "BDUF" is usually the *negative* foil to
  evolutionary design (exhaustive specification before any code). The balanced, authoritative
  treatment is **Martin Fowler, "Is Design Dead?"** — planned and evolutionary design must be
  combined; "in deference to the gods of YAGNI ... when in doubt err on the side of
  simplicity," and simplify the architecture as soon as part of it stops paying its way.
- **How to apply:** Scale up-front design to the **cost of change** and **irreversibility**.
  Data models, module boundaries, and public APIs are expensive to change → design them
  deliberately. Internal implementation details are cheap to change → keep them simple and
  let them evolve. This is the productive synthesis of BDUF with YAGNI.
- **Why it matters:** A little deliberate thought prevents thrash and rework on the decisions
  that are hard to undo; too much up-front detail on the easy-to-change parts is waste.
- **Fetch:** https://martinfowler.com/articles/designDead.html
