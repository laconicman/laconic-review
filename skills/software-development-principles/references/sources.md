# Sources & citation integrity

Consolidated bibliography for citing the principles accurately, plus the misattribution
caveats that keep those citations honest. Use the stable URLs as fetch-on-demand targets
when you need a primary source to ground a design argument. Books are listed first as the
authoritative origin; official docs are listed where nothing replaces them.

When attributing a principle, prefer naming the **person and primary work** ("Liskov, OOPSLA
1987"; "Hunt & Thomas, *The Pragmatic Programmer*"); it lends weight and is verifiable.

## Citation-integrity caveats (read before attributing)
These are the easy things to get wrong:

1. **SOLID:** assembled by **Robert C. Martin**; the **acronym was coined ~2004 by Michael
   Feathers**. Don't credit the acronym to Martin.
2. **OCP** predates Martin — **Bertrand Meyer**, *Object-Oriented Software Construction*
   (1988). **LSP** is **Barbara Liskov's**, not Martin's. Martin grouped them into SOLID.
3. **Occam's razor:** the Latin "entia non sunt multiplicanda praeter necessitatem" is
   **not** in William of Ockham's surviving writings; it is later (the "non sunt
   multiplicanda" phrasing ~1639; the *name* is 19th-century). Attribute the *idea* to
   Ockham, not the slogan.
4. **APO / Knuth:** the quote has a second half — "we should not pass up our opportunities in
   that critical 3%." Don't quote only the "root of all evil" clause. Knuth later called it
   "Hoare's Dictum"; the attribution to Hoare/Dijkstra is itself uncertain.
5. **YAGNI:** the canonical one-liner is **Ron Jeffries'**, popularized by **Fowler**; the
   practice is from **XP / Kent Beck**. DRY's sibling phrase "Once and Only Once" is XP's.
6. **DRY is about knowledge, not text** — quoting the definition without this caveat invites
   the wrong-abstraction mistake.
7. **"Single source of truth" in SwiftUI is Apple's own term** — safe to attribute to Apple's
   data-flow documentation and WWDC sessions.

## By principle

### KISS
- Origin (design culture): Kelly Johnson / U.S. Navy, ~1960. No founding paper.
- https://en.wikipedia.org/wiki/KISS_principle
- Swift framing: Swift.org, **API Design Guidelines** ("Clarity is more important than
  brevity"): https://www.swift.org/documentation/api-design-guidelines/
- WWDC 2016, Session 403, "Swift API Design Guidelines":
  https://developer.apple.com/videos/play/wwdc2016/403/

### DRY + SSOT
- **Andrew Hunt & David Thomas, *The Pragmatic Programmer*** (Addison-Wesley, 1999; 20th
  Anniversary ed. 2019). DRY = Tip 15: "Every piece of knowledge must have a single,
  unambiguous, authoritative representation within a system." Tips index:
  https://pragprog.com/tips/
- https://en.wikipedia.org/wiki/Don%27t_repeat_yourself
- SSOT in SwiftUI (Apple): "Managing model data in your app":
  https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app ;
  "State and data flow": https://developer.apple.com/documentation/swiftui/state-and-data-flow ;
  WWDC 2019, Session 226, "Data Flow Through SwiftUI":
  https://developer.apple.com/videos/play/wwdc2019/226/

### YAGNI
- **Kent Beck, *Extreme Programming Explained*** (Addison-Wesley, 1999/2004), "Simple
  Design." One-liner originated by **Ron Jeffries**.
- **Martin Fowler, "Yagni" (2015):** https://martinfowler.com/bliki/Yagni.html
- Ron Jeffries on the safety conditions:
  https://ronjeffries.com/articles/019-01ff/iter-yagni-skimp/
- https://en.wikipedia.org/wiki/You_aren%27t_gonna_need_it

### BDUF
- **Martin Fowler, "Is Design Dead?":** https://martinfowler.com/articles/designDead.html
  (the balanced treatment of up-front vs evolutionary design).

### SOLID (overview)
- **Robert C. Martin, "Design Principles and Design Patterns" (2000)** and the "Principles of
  OOD" article series: http://butunclebob.com/ArticleS.UncleBob.PrinciplesOfOod ;
  DePaul mirror of the principle papers:
  https://condor.depaul.edu/dmumaugh/OOT/Design-Principles/
- Book: **Robert C. Martin, *Agile Software Development: Principles, Patterns, and
  Practices*** (Prentice Hall, 2002); also *Clean Architecture* (Prentice Hall, 2017).
- Acronym: **Michael Feathers**, ~2004 (author of *Working Effectively with Legacy Code*,
  Prentice Hall, 2004).
- https://en.wikipedia.org/wiki/SOLID

### SRP / OCP / ISP / DIP (within SOLID)
- OCP origin: **Bertrand Meyer**, *Object-Oriented Software Construction* (Prentice Hall,
  1988).
- DIP in Swift: **Protocol-Oriented Programming in Swift**, WWDC 2015, Session 408 (Dave
  Abrahams): https://developer.apple.com/videos/play/wwdc2015/408/
- Dependency injection library: **Point-Free swift-dependencies**:
  https://github.com/pointfreeco/swift-dependencies ;
  https://pointfreeco.github.io/swift-dependencies/main/documentation/dependencies/

### LSP
- **Barbara Liskov, "Data Abstraction and Hierarchy," OOPSLA-87 keynote** (ACM SIGPLAN
  Notices 23(5), May 1988, pp. 17–34), doi:10.1145/62139.62141.
- **Barbara Liskov & Jeannette Wing, "A Behavioral Notion of Subtyping," ACM TOPLAS 16(6),
  Nov 1994**, doi:10.1145/197320.197383: https://dl.acm.org/doi/10.1145/197320.197383
- https://en.wikipedia.org/wiki/Liskov_substitution_principle

### Low coupling & high cohesion
- **W. P. Stevens, G. J. Myers & L. L. Constantine, "Structured Design," IBM Systems
  Journal, 1974** (origin of coupling & cohesion).
- **Edward Yourdon & Larry Constantine, *Structured Design*** (Yourdon Press 1975;
  Prentice-Hall 1979).
- **Glenford Myers, *Reliable Software Through Composite Design*** (1975) — "module strength"
  for cohesion.
- Coupling/cohesion spectrum: **Meilir Page-Jones, *The Practical Guide to Structured Systems
  Design*** (Yourdon Press; 1st ed. 1980, 2nd ed. 1988):
  https://archive.org/details/practicalguideto0000page_e3j1
- As GRASP design patterns: **Craig Larman, *Applying UML and Patterns*** (3rd ed., Prentice
  Hall, 2004): https://en.wikipedia.org/wiki/GRASP_(object-oriented_design)
- https://en.wikipedia.org/wiki/Coupling_(computer_programming) ·
  https://en.wikipedia.org/wiki/Cohesion_(computer_science)

### APO (Avoid Premature Optimization)
- **Donald E. Knuth, "Structured Programming with go to Statements," ACM Computing Surveys
  6(4), Dec 1974, §1**, doi:10.1145/356635.356640. Full sourced quote (with attribution
  trail to Hoare/Dijkstra): https://en.wikiquote.org/wiki/Donald_Knuth
- Apple measure-first guidance: "Improving your app's performance":
  https://developer.apple.com/documentation/xcode/improving-your-app-s-performance ;
  WWDC 2019, Session 411, "Getting Started with Instruments":
  https://developer.apple.com/videos/play/wwdc2019/411

### Occam's razor
- Attributed to **William of Ockham** (c. 1287–1347); standard Latin slogan is later (see
  caveats above). https://en.wikipedia.org/wiki/Occam%27s_razor ;
  https://www.britannica.com/topic/Occams-razor

## Counterpoints (anti-cargo-cult)
- **Sandi Metz, "The Wrong Abstraction" (2016)** — "duplication is far cheaper than the wrong
  abstraction": https://sandimetz.com/blog/2016/1/20/the-wrong-abstraction
- **Dan North, "CUPID — for joyful coding"** — properties over principles; SRP-by-layer can
  hurt cohesion: https://dannorth.net/cupid-for-joyful-coding/
- **Casey Muratori, "Clean Code, Horrible Performance"** (SE-Radio 577 interview) —
  abstraction's performance cost on hot paths:
  https://se-radio.net/2023/08/se-radio-577-casey-muratori-on-clean-code-horrible-performance/

## Community sources for Swift idioms
Respected, non-hyped voices used for the Swift examples (lead with Apple/Swift.org first):
- **Point-Free** (Brandon Williams & Stephen Celis) — DI, composability, SSOT:
  https://www.pointfree.co
- **Matteo Manferdini** — SwiftUI architecture, domain vs application logic:
  https://matteomanferdini.com (e.g. https://matteomanferdini.com/swiftui-mv-pattern/)
- **AzamSharp (Mohammad Azam)** — the MV position:
  https://azamsharp.com/2024/01/09/is-mvvm-dead-in-swiftui.html
- **Swift by Sundell (John Sundell):** https://www.swiftbysundell.com
- **objc.io** (Chris Eidhof, Florian Kugler) — *Advanced Swift*, *Thinking in SwiftUI*:
  https://www.objc.io
- iOS dev source directory (per user preference): https://iosdevdirectory.com
