# Swift / Apple-platform idioms

Short, modern, commented Swift examples mapping each principle to Apple-platform practice.
Examples target current APIs (iOS 17+ Observation, async/await, value types) and prefer
official Apple docs and WWDC, then respected community sources. Citations are in code
comments per house style. Keep clarity over brevity; these are illustrations, not
copy-paste production code.

For SwiftUI *architecture* depth (MVC/MVVM, controllers, view decomposition, previews),
**defer to the `swiftui-foundations` skill** — this file only shows the principle-to-idiom
mapping.

## Table of contents
- [SSOT in SwiftUI (DRY / SSOT)](#ssot-in-swiftui-dry--ssot)
- [DIP via protocol + initializer injection](#dip-via-protocol--initializer-injection)
- [DIP via SwiftUI environment injection](#dip-via-swiftui-environment-injection)
- [swift-dependencies for controllable dependencies](#swift-dependencies-for-controllable-dependencies)
- [SRP / high cohesion: domain vs application logic](#srp--high-cohesion-domain-vs-application-logic)
- [The MV vs MVVM choice (a trade-off)](#the-mv-vs-mvvm-choice-a-trade-off)
- [OCP: add a conformer, do not edit a switch](#ocp-add-a-conformer-do-not-edit-a-switch)
- [ISP: split fat protocols, compose with &](#isp-split-fat-protocols-compose-with-)
- [LSP: value types over inheritance](#lsp-value-types-over-inheritance)
- [KISS / Occam in API design](#kiss--occam-in-api-design)
- [APO: measure before optimizing](#apo-measure-before-optimizing)
- [Wrapping a framework behind a seam (Core Bluetooth, Core ML)](#wrapping-a-framework-behind-a-seam-core-bluetooth-core-ml)
- [Library vs roll-your-own (YAGNI / Occam / DRY)](#library-vs-roll-your-own-yagni--occam--dry)

---

## SSOT in SwiftUI (DRY / SSOT)
Apple's own term. Truth has one owner; everything else derives from it.

```swift
import SwiftUI
import Observation

// Shared, observable source of truth (Observation framework, iOS 17+).
// Apple: "Managing model data in your app" — provide a single source of truth.
@Observable
final class Cart {
    private(set) var items: [Item] = []            // owners expose read-only where possible (low coupling)
    var total: Decimal { items.reduce(0) { $0 + $1.price } }  // derived, never stored twice (DRY)
    func add(_ item: Item) { items.append(item) }
}

struct CartView: View {
    @State private var cart = Cart()               // this view CREATES & OWNS the truth
    var body: some View {
        VStack {
            List(cart.items) { ItemRow(item: $0) }
            Text(cart.total, format: .currency(code: "USD"))  // read from the one source
        }
    }
}

// A child that EDITS truth owned elsewhere takes a binding, not its own copy.
struct QuantityStepper: View {
    @Binding var quantity: Int                      // reference to truth, not a duplicate
    var body: some View { Stepper("Qty \(quantity)", value: $quantity, in: 1...99) }
}

// Two-way editing of an @Observable model's properties: @Bindable (iOS 17+).
struct EditItemView: View {
    @Bindable var item: Item
    var body: some View { TextField("Name", text: $item.name) }
}
```
Anti-pattern to avoid: copying `cart.items` into a second `@State` array in a child view —
the copies drift and you are back to a multi-source-of-truth bug.
Sources: https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app ·
https://developer.apple.com/videos/play/wwdc2019/226/ (Data Flow Through SwiftUI).

## DIP via protocol + initializer injection
The plainest, no-magic dependency inversion. High-level code depends on an abstraction.

```swift
// Abstraction the high-level code depends on (not URLSession, not a concrete client).
protocol WeatherService: Sendable {
    func currentTemperature(for city: String) async throws -> Measurement<UnitTemperature>
}

// Detail #1: the real implementation.
struct LiveWeatherService: WeatherService {
    func currentTemperature(for city: String) async throws -> Measurement<UnitTemperature> {
        // ...URLSession call, decode...
        .init(value: 21, unit: .celsius)
    }
}

// Detail #2: a deterministic stub for tests and SwiftUI previews (cheap because of DIP).
struct StubWeatherService: WeatherService {
    var fixed: Measurement<UnitTemperature>
    func currentTemperature(for city: String) async throws -> Measurement<UnitTemperature> { fixed }
}

@Observable
final class WeatherViewModel {
    private let service: any WeatherService          // depends on the abstraction (DIP, low coupling)
    private(set) var temperature: Measurement<UnitTemperature>?
    init(service: any WeatherService) { self.service = service }   // injected, not constructed here
    func refresh(city: String) async {
        temperature = try? await service.currentTemperature(for: city)
    }
}
// Production: WeatherViewModel(service: LiveWeatherService())
// Test:       WeatherViewModel(service: StubWeatherService(fixed: .init(value: 30, unit: .celsius)))
```
Foundation: Protocol-Oriented Programming, WWDC 2015 (Dave Abrahams):
https://developer.apple.com/videos/play/wwdc2015/408/

## DIP via SwiftUI environment injection
Inject a dependency through the environment so deep view trees do not thread it manually.

```swift
// Custom environment value (classic form).
private struct WeatherServiceKey: EnvironmentKey {
    static let defaultValue: any WeatherService = LiveWeatherService()
}
extension EnvironmentValues {
    var weatherService: any WeatherService {
        get { self[WeatherServiceKey.self] }
        set { self[WeatherServiceKey.self] = newValue }
    }
}

// Read it where needed:
struct ForecastView: View {
    @Environment(\.weatherService) private var weatherService
    var body: some View { /* use weatherService */ Text("…") }
}

// Inject at a boundary (e.g. previews/tests get a stub for free):
#Preview {
    ForecastView().environment(\.weatherService, StubWeatherService(fixed: .init(value: 18, unit: .celsius)))
}
```
iOS 18+ shrinks the boilerplate with the `@Entry` macro — but signal the availability cost
rather than treating the newer API as free:

```swift
extension EnvironmentValues {
    #if compiler(>=6.0)        // @Entry needs the iOS 18 SDK / Swift 6 toolchain
    @Entry var weatherService: any WeatherService = LiveWeatherService()
    #endif
}
```
Source: https://developer.apple.com/documentation/swiftui/environmentvalues

## swift-dependencies for controllable dependencies
When you have *many* implicit dependencies that hurt testability (current date, UUIDs,
clocks, file system), Point-Free's swift-dependencies gives a uniform, SwiftUI-environment-
style mechanism. This is a YAGNI call: adopt it when the pain is real, not by default.

```swift
import Dependencies   // github.com/pointfreeco/swift-dependencies

@Observable
final class TimerModel {
    @ObservationIgnored @Dependency(\.continuousClock) var clock   // controllable in tests
    @ObservationIgnored @Dependency(\.date.now) var now
    // In tests: withDependencies { $0.continuousClock = ImmediateClock() } operation: { … }
}
```
Source / docs: https://github.com/pointfreeco/swift-dependencies ·
https://pointfreeco.github.io/swift-dependencies/main/documentation/dependencies/

## SRP / high cohesion: domain vs application logic
The cleanest cohesion boundary in app code (Manferdini's framing, which holds up well):
**domain logic** — entities and business rules that would exist regardless of UI — lives in
**model types**; **application logic** — coordination, navigation, and presentation state —
lives in **controllers / view models**; **views render and forward intent**. Each type then
has one reason to change (SRP) and stays cohesive.

```swift
// DOMAIN logic — a business rule, independent of any screen. Belongs on the model.
struct Subscription {
    let renewalDate: Date
    let trialDays: Int
    func isInTrial(asOf now: Date, calendar: Calendar = .current) -> Bool {
        guard let trialEnd = calendar.date(byAdding: .day, value: trialDays, to: renewalDate)
        else { return false }
        return now < trialEnd
    }
}

// APPLICATION logic — what THIS screen does with the domain. Belongs on the view model.
@Observable
final class SubscriptionScreenModel {
    private let subscription: Subscription
    private let now: () -> Date
    init(subscription: Subscription, now: @escaping () -> Date = Date.init) {
        self.subscription = subscription; self.now = now
    }
    var bannerText: String { subscription.isInTrial(asOf: now()) ? "Trial active" : "Subscribed" }
}

// VIEW — renders state, forwards user intent, holds no business rule.
struct SubscriptionView: View {
    @State private var model: SubscriptionScreenModel
    var body: some View { Text(model.bannerText) }
}
```
Putting `isInTrial` math inside the view mixes domain logic into presentation (low cohesion,
hard to test). Also decompose large `body`s into small subviews — that *is* SRP at the view
level. Deeper guidance: the `swiftui-foundations` skill.

## The MV vs MVVM choice (a trade-off)
There is a genuine, unsettled debate, so present it as a trade-off, not a verdict.
- **MV ("Model–View"):** views talk directly to `@Observable` model objects; no per-view
  view model. Apple's recent sample code uses this; proponents (Thomas Ricouard, AzamSharp)
  argue "the SwiftUI View is the view model" and an extra layer is needless ceremony.
- **MVVM / a dedicated presentation type:** extract a view model when a screen accumulates
  non-trivial presentation logic, validation, or coordination — keeping the view cohesive
  and the logic testable (Manferdini's position, which this skill leans toward: the domain
  vs application-logic split above is the substance; MV is essentially MVC rebranded and
  still benefits from somewhere to put application logic).

Practical rule consistent with KISS/YAGNI: start MV-simple; introduce a presentation type
the moment a view's logic stops being trivial. Don't add view models reflexively, and don't
cram business rules into views to avoid one. Full treatment: `swiftui-foundations`.
Sources: https://azamsharp.com/2024/01/09/is-mvvm-dead-in-swiftui.html ·
https://matteomanferdini.com/swiftui-mv-pattern/

## OCP: add a conformer, do not edit a switch
Extend behavior by adding a type, not by modifying working code.

```swift
protocol Discount {
    func apply(to price: Decimal) -> Decimal
}
struct PercentageDiscount: Discount {
    let rate: Decimal
    func apply(to price: Decimal) -> Decimal { price * (1 - rate) }
}
struct FixedDiscount: Discount {
    let amount: Decimal
    func apply(to price: Decimal) -> Decimal { max(0, price - amount) }
}
// New rule? Add `struct BogoDiscount: Discount { … }`. Existing code is untouched (closed),
// the system is extended (open). Contrast with a growing `switch discountKind { … }`.
```

## ISP: split fat protocols, compose with &
Don't force read-only clients to depend on write/delete they never call.

```swift
// Fat: every consumer must know the whole surface.
protocol DataStore {
    func read() throws -> Data
    func write(_ data: Data) throws
    func delete() throws
}

// Segregated, role-focused protocols (ISP):
protocol DataReading { func read() throws -> Data }
protocol DataWriting { func write(_ data: Data) throws }

// Compose only where a client truly needs both (protocol composition):
typealias ReadWriteStore = DataReading & DataWriting

// A cache warmer depends on DataReading only — minimal knowledge (low coupling).
struct CacheWarmer { let source: any DataReading }
```
The standard library is the canonical example: `Equatable`, `Hashable`, `Comparable` are
separate, composable protocols rather than one mega-protocol.

## LSP: value types over inheritance
Model variants as distinct types behind a protocol; no subtype is forced to lie about its
behavior.

```swift
protocol Shape { var area: Double { get } }
struct Rectangle: Shape {
    var width: Double; var height: Double
    var area: Double { width * height }
}
struct Square: Shape {
    var side: Double
    var area: Double { side * side }
}
// The infamous LSP violation (a Square subclass that breaks Rectangle's set-width/height
// invariant) cannot occur here: Square is not a Rectangle, just another Shape.
```
Prefer `final` classes when you do use classes — Swift even defaults toward value semantics
to keep substitution honest.

## KISS / Occam in API design
Swift.org: clarity at the point of use is the top goal; brevity is not.

```swift
// Over-clever (fails KISS/Occam): generic gymnastics with no caller benefit.
func process<T, U>(_ input: T, with transform: (T) -> U, _ flag: Bool = false) -> U? { … }

// Clear (clarity over brevity): the call site reads like a sentence.
func formattedTitle(for article: Article) -> String { … }
// usage: let title = formattedTitle(for: article)
```
Source: https://www.swift.org/documentation/api-design-guidelines/

## APO: measure before optimizing
Confirm a real cost, then find the hot path, then optimize only that.

```swift
import Testing   // or XCTest's measure {}

@Test func parsingIsFastEnough() {
    // Establish whether there is even a problem before touching the code.
    // (Then profile in Instruments → Time Profiler to locate the critical 3%.)
    let payload = SamplePayloads.large
    _ = Parser().parse(payload)
}
```
Apple's measure-first loop: gather info → measure to find causes → change one thing →
compare a *before*/*after* Instruments profile. Don't trade clarity for speed on cold paths.
Source: https://developer.apple.com/documentation/xcode/improving-your-app-s-performance

## Wrapping a framework behind a seam (Core Bluetooth, Core ML)
A textbook DIP/low-coupling move on Apple platforms: depend on a narrow protocol you own,
not directly on the framework, so high-level code is testable and the framework is swappable.

```swift
// Core Bluetooth: a small seam over CBCentralManager for your app's actual needs.
protocol PeripheralScanning {
    func startScanning() async
    var discoveries: AsyncStream<Discovery> { get }
}
// Live impl wraps CBCentralManager; a mock impl drives tests with scripted discoveries.
// Nordic's CoreBluetoothMock library exists precisely for this (CBMCentralManager mirrors
// CBCentralManager): https://github.com/NordicSemiconductor/IOS-CoreBluetooth-Mock
```
```swift
// Core ML: depend on your own classifying protocol, not the generated MLModel class.
struct Classification: Sendable { let label: String; let confidence: Double }
protocol ImageClassifying {
    func classify(_ image: CGImage) async throws -> [Classification]
}
struct CoreMLClassifier: ImageClassifying {   // wraps VNCoreMLModel / the generated model
    func classify(_ image: CGImage) async throws -> [Classification] { /* Vision request */ [] }
}
struct StubClassifier: ImageClassifying {     // deterministic results for tests/previews
    var results: [Classification]
    func classify(_ image: CGImage) async throws -> [Classification] { results }
}
```
The view model holds `any ImageClassifying` (DIP) and never imports Vision/CoreML — the
detail depends on the abstraction, not the reverse.

## Library vs roll-your-own (YAGNI / Occam / DRY)
Choosing a dependency is itself a principles decision:
- **Reach for a vetted SPM** when the capability is substantial and well-tested and you
  would otherwise re-implement (and re-test) it yourself — e.g. `swift-algorithms` for
  `chunked`, `windows`, `uniqued`; `SwifterSwift` for broad, battle-tested conveniences.
  That respects DRY (don't re-derive solved logic) and high cohesion (keep your code about
  your domain).
- **Inline a few lines** when the needed bit is tiny relative to the dependency. Adding a
  whole library for a one-liner adds coupling, build cost, and a maintenance liability — a
  YAGNI/Occam violation.
- **Heuristic:** is the snippet you need clearly smaller and simpler than the library, and
  do you need only it? Inline. Otherwise, prefer the well-maintained package.

Sources: https://github.com/apple/swift-algorithms · https://github.com/SwifterSwift/SwifterSwift
