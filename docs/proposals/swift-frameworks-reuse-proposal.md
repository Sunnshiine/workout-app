# Swift Frameworks and Reuse Proposal

Date: 2026-06-02

## Purpose

This proposal evaluates modern Swift/iOS frameworks and libraries that could reduce hand-written infrastructure in WorkoutTracker without diluting the app's domain model or Liquid Glass direction.

The goal is not to add popular packages because they are popular. The goal is to find deep modules: small interfaces that put a lot of behavior, testability, and reuse behind one well-named seam.

## Current Repo Baseline

WorkoutTracker is already using the right platform foundation for an iOS 26 app:

- SwiftUI and Observation for UI/state.
- SwiftData for local cache and pending-write persistence.
- Native Liquid Glass APIs through `.glassEffect`, `GlassEffectContainer`, and `.buttonStyle(.glass)`.
- Swift Testing for unit/component coverage.
- A deliberately dependency-light SwiftPM package.

That is a good baseline. The main reuse opportunities are not in replacing SwiftUI or SwiftData. They are in reducing repeated dependency wiring, making time/network/defaults controllable, tightening visual regression coverage, and selectively using Apple Swift packages for collections/algorithms where the app currently carries manual indexing logic.

Important repo constraints:

- The Xcode app target has `IPHONEOS_DEPLOYMENT_TARGET = 26.0`, and ADR 0004 says Views assume iOS 26 with no Liquid Glass fallback paths.
- `Package.swift` currently declares iOS 18 because the SwiftPM library target excludes `WorkoutTracker/Views`, `GoogleAuth.swift`, and the app entry point. That package setting should not be interpreted as the UI deployment target.
- Any proposal touching Views, Google auth, or app lifecycle must be verified through Xcode, not only `swift test`.
- The Sheet remains the source of truth. Any library that weakens Visible Writable Row targeting, pending-write safety, or workbook evidence should be rejected.

## Liquid Glass Constraint

Apple's iOS 26 Liquid Glass support is native SwiftUI surface area, not a general third-party dependency category. Apple documents Liquid Glass for custom SwiftUI views via `glassEffect(_:in:)`, `GlassEffectContainer`, and related modifiers; standard SwiftUI components also pick up the system treatment when the app is built with the modern SDK.

Repo implication:

- Prefer native SwiftUI Liquid Glass APIs.
- Do not wrap the entire UI in a third-party Liquid Glass component kit.
- If repeated glass styling is now painful, add a tiny internal `Theme`/view helper that still calls Apple APIs directly.

Sources:

- Apple, [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- Apple, [Liquid Glass technology overview](https://developer.apple.com/documentation/technologyoverviews/liquid-glass)
- Existing repo decision: [ADR 0004: Liquid Glass Design System](../adr/0004-liquid-glass-design-system.md)

## Recommendation Summary

| Priority | Library or framework | Recommendation | Why |
| --- | --- | --- | --- |
| 1 | `swift-dependencies` | Pilot only | Best match for repeated manual dependency seams: clocks, dates, user defaults, URL loading, UUIDs, previews, tests. |
| 2 | Native SwiftUI Liquid Glass + internal glass primitives | Pilot internally | Keeps Liquid Glass native while removing repeated `.glassEffect`/shape/palette boilerplate. |
| 3 | `swift-snapshot-testing` | Do not add now | Revisit only after Ralph screenshots miss a repeated visual regression. |
| 4 | Apple `swift-collections` and `swift-algorithms` | Do not add now | Adopt only after at least two repeated ordering/uniqueness invariants or one real bug. |
| 5 | BackgroundTasks / ActivityKit / Swift Charts | Separate future product issues | Useful system surfaces, but not dependency-reuse cleanup. |
| 6 | CoreXLSX | Defer behind API-captured fixtures | API-captured `SheetSnapshot` fixtures are stronger first evidence for Google Sheets behavior. |
| 7 | Swift OpenAPI Generator / Google REST client | Defer | Strong technology, but current Google Sheets/Drive risk is spreadsheet semantics, not HTTP ceremony. |
| 8 | TCA / `swift-navigation` | Defer wholesale adoption | Powerful, but too much architecture churn for the current app. Revisit only if navigation/state composition becomes the dominant pain. |
| 9 | Third-party Liquid Glass kits | Avoid for now | Too young, duplicate Apple APIs, and risk fighting platform behavior. |

## Adversarial Review Outcome

An adversarial sub-agent reviewed the first draft and argued that it overreached. The consensus from that review is:

- Keep the dependency-light direction.
- Treat `swift-dependencies` as a reversible pilot, not an architecture decision.
- Treat native Liquid Glass helpers as a tiny internal cleanup, not a UI framework.
- Demote snapshot testing, collections, BackgroundTasks, ActivityKit, Swift Charts, and CoreXLSX unless they map to a concrete bug, repeated maintenance cost, or separate product issue.
- Add a hard rule: no package should be added unless the first PR deletes or materially simplifies enough app-owned code to earn the dependency.

## 1. Pilot `swift-dependencies`, But Do Not Make It The App Architecture

Source:

- Point-Free, [`swift-dependencies`](https://github.com/pointfreeco/swift-dependencies)
- Current docs via Context7 confirmed `@Dependency`, `withDependencies`, preview/test overrides, and SwiftUI view injection support.

### Why It Fits

The repo already has several seams that exist only to control outside systems:

- `GoogleSheetsClient` accepts `tokenProvider` and `load`.
- `RestTimer` accepts `RestClock` and a notification scheduler.
- `SettingsStore`, `WorkoutStore`, and tests manually pass `UserDefaults` suites.
- Multiple tests create fresh `Date`, `UUID`, `ModelContainer`, and fake sync objects.
- `Task.sleep`-style timing and main-queue behavior are easy to accidentally make nondeterministic.

`swift-dependencies` is explicitly built for this class of problem: API clients, file access, user defaults, clocks, UUIDs, dates, and other outside systems. Its README calls out deterministic tests and SwiftUI previews as core use cases.

### Where To Use It First

Start with one vertical slice, not the whole app. The pilot should be framed as a reversible experiment:

- `RestTimer`
- `RestPillView`
- `RestHapticSchedule` tests
- `SessionCoordinator` tests that currently pass clock/timer objects manually

Then consider:

- `SettingsStore` defaults access.
- `GoogleSheetsClient` token/load transport.
- `SyncCoordinator` last-performed backfill timing and logging dependencies.

### Before

```swift
@MainActor
protocol RestClock: AnyObject {
    var now: Date { get }
}

@MainActor
final class SystemRestClock: RestClock {
    var now: Date { Date() }
}

@MainActor
@Observable
final class RestTimer {
    @ObservationIgnored private let clock: any RestClock
    @ObservationIgnored private let notificationScheduler: (any RestNotificationScheduling)?

    init(
        clock: any RestClock = SystemRestClock(),
        notificationScheduler: (any RestNotificationScheduling)? = nil
    ) {
        self.clock = clock
        self.notificationScheduler = notificationScheduler
    }
}
```

### After

The pilot should convert the whole `RestTimer` dependency shape or not convert it at all. A partial migration that keeps initializer injection for notifications while using task-local dependency access for time is worse than the current code.

```swift
import Dependencies

private enum RestNotificationSchedulerKey: DependencyKey {
    static let liveValue: (any RestNotificationScheduling)? = RestNotificationCenterScheduler.shared
    static let testValue: (any RestNotificationScheduling)? = nil
}

@MainActor
@Observable
final class RestTimer {
    @ObservationIgnored
    @Dependency(\.date.now) private var now

    @ObservationIgnored
    @Dependency(\.restNotificationScheduler) private var notificationScheduler

    func start(duration: TimeInterval, origin: ActiveSetID?) {
        deadline = now.addingTimeInterval(duration)
        notificationScheduler?.schedule(deadline: deadline)
    }
}
```

Test setup becomes scoped rather than threaded through every initializer:

```swift
let timer = withDependencies {
    $0.date.now = Date(timeIntervalSince1970: 100)
} operation: {
    RestTimer()
}
```

The pilot must compare this against the current explicit initializer injection. If the current code remains clearer after including `remaining`, `dismiss`, notification scheduling, and `SessionCoordinator`'s separate transition clock, do not adopt the package.

### Why This Is Elegant

This deepens the dependency seam. Today, each module invents its own tiny adapter. Afterward, the interface for controllable time/defaults/network can be consistent across the app. That improves locality: test setup and preview setup become obvious, and dependency behavior stops leaking into every initializer.

### Risks

- `swift-dependencies` shines most in single-entry systems. The app is not TCA-based, so use it conservatively.
- Do not mix global dependency access with ad hoc initializer injection in the same module unless there is a clear migration path.
- Keep the first slice small enough to revert if it makes the code less readable.

### Acceptance Criteria For The Pilot

- Fewer custom clock/defaults/test adapters in the touched slice.
- Tests get shorter without losing explicitness.
- No production behavior change.
- `swift test` remains fast.
- The PR can be reverted without touching unrelated stores or views.
- No module mixes ad hoc initializer injection and `@Dependency` for the same dependency family.

## 2. Keep Liquid Glass Native, Pilot Internal Glass Primitives

Sources:

- Apple, [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- Repo skill/reference guidance for iOS 26 Liquid Glass: prefer native `glassEffect`, `GlassEffectContainer`, and glass button styles. This app's View layer assumes iOS 26, so this proposal does not add fallback UI paths.

### Why It Fits

The repo now has repeated glass/card/pill patterns:

- `SessionView`
- `OnboardingView`
- `EmptyStateView`
- `DeveloperToolsView`
- `MoveOnCelebrationView`
- `RestPillView`
- `ExerciseSection`

ADR 0004 intentionally avoided custom modifiers while the app was small. The app has now grown enough that a small internal primitive may be justified, but this should still be a pilot rather than an immediate design-system expansion.

### Before

```swift
.padding(Theme.cardSpacing * 2)
.glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
```

Each caller must remember:

- shape
- corner radius
- interactivity
- palette fill fallback
- whether it belongs inside an existing `GlassEffectContainer`

### After

Do not add one blunt `.workoutGlassCard()` modifier. Existing call sites include cards, capsules, morphing onboarding IDs, grouped containers, and the custom celebration lens. The helper should centralize effect style and shape naming while leaving container placement and identity at the call site.

```swift
enum WorkoutGlass {
    static func card(interactive: Bool = false) -> Glass {
        interactive ? .regular.interactive() : .regular
    }

    static let cardCornerRadius = Theme.cardCornerRadius
    static let capsule: Glass = .regular
}
```

Call sites still state whether they are in a container and whether they need an identity:

```swift
GlassEffectContainer(spacing: Theme.cardSpacing) {
    ExerciseSection(...)
        .glassEffect(WorkoutGlass.card(), in: .rect(cornerRadius: WorkoutGlass.cardCornerRadius))
}
```

Onboarding keeps its morphing identity explicit:

```swift
OnboardingCard(...)
    .glassEffect(WorkoutGlass.card(), in: .rect(cornerRadius: WorkoutGlass.cardCornerRadius))
    .glassEffectID("onboarding", in: namespace)
```

### Why This Is Elegant

This removes repeated styling knowledge without importing a UI kit. The seam is internal, shallow enough to audit, and aligned with the platform. If Apple adjusts Liquid Glass behavior in iOS 26.x, one app-specific module owns the app's response.

The first implementation should migrate only exact duplicates. It should not opportunistically restyle nearby controls.

### Risks

- Too many generic modifiers would recreate a design system framework prematurely.
- Names must stay domain-specific. Prefer `workoutGlassCard` over `glassSurfaceStyleVariantThree`.
- Do not hide layout inside the modifier; keep it to visual surface behavior.
- Because Views are excluded from `Package.swift`, this must use an Xcode build/test gate.

## 3. Do Not Add `swift-snapshot-testing` Yet

Source:

- Point-Free, [`swift-snapshot-testing`](https://github.com/pointfreeco/swift-snapshot-testing)
- Context7 docs confirmed SwiftUI image snapshots, device layouts, trait collections, Swift Testing support, and XCTest integration.

### Why It May Eventually Fit

`docs/TESTING.md` currently says snapshot testing is deferred until a specific visual regression problem justifies the maintenance cost. Ralph screenshots currently own static visual checks.

Liquid Glass and palette work could eventually justify snapshots, but adding them now would create a second visual baseline before the repo has evidence that Ralph is insufficient.

Future use, only after a repeated missed regression:

- `MoveOnCelebrationView`
- `ActiveSetCard`
- `SessionView` seeded fixture screenshot equivalent
- `OnboardingView` sign-in and picker states
- `Theme` palette variants

### Before

```swift
@Test func activeSetPresentationShowsLoggedState() {
    #expect(state.badge == "Logged")
    #expect(state.isLogButtonEnabled == false)
}
```

This protects state, not pixels.

### Future After

```swift
@Suite(.snapshots(record: .failed))
struct MoveOnCelebrationSnapshots {
    @Test func completeSessionGlassBloom() {
        assertSnapshot(
            of: MoveOnCelebrationView(...),
            as: .image(layout: .device(config: ViewImageConfig.workoutIPhone17Pro))
        )
    }
}
```

### Why This Would Be Elegant Later

It complements the existing testing policy instead of replacing it. Keep behavioral assertions in Swift Testing. Add snapshots only where the user would notice a visual regression and where iOS 26 Liquid Glass makes “looks right” hard to infer from state.

### Risks

- Liquid Glass rendering can vary by OS, simulator, color scheme, and GPU path.
- Snapshot churn can become noise if applied broadly.
- The first adoption should define one simulator/runtime baseline and one recording policy.
- Snapshot tests should not replace Ralph screenshot checks until the repo has proven they are less noisy.

### Acceptance Criteria For A Future Pilot

- At most 3-5 snapshot tests initially.
- Snapshots use the repo's agreed iPhone 17 Pro / iOS 26.3.1 baseline.
- Snapshots run only in the Xcode/UI visual gate, not the fastest `swift test` loop.
- Failures produce useful diffs rather than vague screenshot artifacts.

## 4. Do Not Add Apple `swift-collections` Or `swift-algorithms` Yet

Sources:

- Apple, [`swift-collections`](https://github.com/apple/swift-collections)
- Swift.org, [Introducing Swift Collections](https://www.swift.org/blog/swift-collections/)
- Swift.org, [Announcing Swift Algorithms](https://www.swift.org/blog/swift-algorithms/)

### Why They Fit

WorkoutTracker has many ordered domain concepts:

- Week/Day order
- Pending write flush order
- Open Exercises
- Superset pair membership
- Last Performed lookup precedence
- visible Sheet rows and role columns

The app currently uses arrays, sets, dictionaries, and manual loops. Most of that is fine. A dependency is justified only where a collection type removes a real invariant from caller code.

Examples:

- `OrderedSet` for unique exercises while preserving Sheet order.
- `OrderedDictionary` for tab/exercise lookup where order matters.
- `Deque` for queues where front removal becomes common.
- `chunked`, `unique`, or related algorithms where parser loops become clearer.

### Before

```swift
var seenNames = Set<String>()
var exercises: [(name: String, baseName: String)] = []

for week in block.weeks {
    for session in week.days {
        for exercise in session.exercises where seenNames.insert(exercise.name).inserted {
            exercises.append((exercise.name, exercise.baseName))
        }
    }
}
```

### Possible Future After

```swift
let exercises = OrderedSet(
    block.weeks
        .flatMap(\.days)
        .flatMap(\.exercises)
        .map { ExerciseIdentity(name: $0.name, baseName: $0.baseName) }
)
```

### Why This Is Elegant

It makes ordering and uniqueness explicit in the type instead of in every loop. That improves leverage when the same invariant appears across parser, writer, and progression modules.

### Risks

- Adding a package for one loop is not worth it.
- Generic collection transforms can become harder to debug than explicit loops in Sheet parsing.
- The Sheet layout interpreter is domain-heavy; do not hide domain rules behind clever sequence chains.

### Adoption Rule

Do not add either package now. Adopt only when one package type replaces at least two repeated invariants or removes a bug-prone manual index path.

The `uniqueExercises` example above is not enough by itself. It must first answer whether uniqueness is by full Exercise name, base name, or some explicit identity type.

## 5. Separate Future Issue: BackgroundTasks For Opportunistic Sync

Sources:

- Apple, [SwiftUI `backgroundTask`](https://developer.apple.com/documentation/swiftui/backgroundtask)
- Apple, [Using background tasks to update your app](https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app)

### Why It May Fit

`SyncCoordinator` currently owns foreground sync, pending-write flush, conflict state, and last-performed backfill. The app also has a product tension: the Sheet is the source of truth, but athletes should not need to babysit sync.

BackgroundTasks could help with:

- Opportunistic pending-write flush after the athlete leaves the app.
- Periodic content refresh so a coach-uploaded Block has a better chance of appearing before the athlete opens the app.
- Last Performed backfill continuation outside the main interaction path.

### Before

```swift
.task {
    if workout.block == nil, let id = settings.spreadsheetId {
        await sync.sync(spreadsheetId: id)
        workout.reload()
    }
}
```

### After

```swift
WindowGroup {
    RootView(...)
}
.backgroundTask(.appRefresh("sync-configured-sheet")) {
    await syncBackgroundConfiguredSheet()
}
```

### Why This Is Elegant

The framework would not replace `SyncCoordinator`; it would give the coordinator another scheduling surface. The existing `SheetsClient`, pending-write safety, and conflict semantics stay app-owned.

### Risks

- Background execution is opportunistic and not guaranteed.
- OAuth/keychain refresh behavior must be tested in a background launch.
- A background flush must never discard pending writes or hide conflicts.
- This needs careful Info.plist/capability setup and UI messaging so users do not assume instant sync.

### Recommendation

Explore only after the foreground sheet-switch/pending-write contract is stable. The first slice should schedule a safe no-op/diagnostic background task before attempting a real pending-write flush.

## 6. Separate Future Issue: ActivityKit For Rest Timer System Presence

Source:

- Apple, [ActivityKit](https://developer.apple.com/documentation/ActivityKit/)

### Why It May Fit

`RestTimer`, `RestPillView`, `RestNotificationScheduler`, and haptics already implement a lot of rest-specific system behavior. A rest timer is a natural Live Activity: it has a clear start, countdown, end, and user value outside the app.

### Before

```swift
RestPillView(restTimer: restTimer)
notificationScheduler.schedule(deadline: deadline)
```

The timer is visible in-app, and the user gets a local notification at the end.

### After

```swift
let activity = try Activity<RestActivityAttributes>.request(
    attributes: .init(kind: restKind),
    content: .init(state: .init(deadline: deadline), staleDate: deadline)
)
```

The in-app pill remains the main Liquid Glass surface. ActivityKit adds Lock Screen/Dynamic Island glanceability through a WidgetKit extension.

### Why This Is Elegant

It uses the platform surface built for live, glanceable activity state instead of inventing a persistent overlay or repeatedly scheduling notifications. It also keeps Session logic out of the Live Activity; only the active rest timer crosses the seam.

### Risks

- Requires a widget extension and entitlement/configuration work.
- Live Activities are not a general background execution mechanism.
- Updates are constrained and should not be used for every Set or Session state change.
- The activity must degrade cleanly when Live Activities are disabled.

### Recommendation

Worth exploring after the in-app rest timer is settled. Do not start here if the goal is immediate code deletion; start here if the goal is a better rest experience.

This is a product/platform improvement, not a refactor to remove manual code. It belongs in its own issue.

## 7. Defer CoreXLSX Behind API-Captured Sheet Fixtures

Source:

- CoreOffice, [CoreXLSX](https://github.com/CoreOffice/CoreXLSX)

### Why It Is Tempting

`LocalWorkbookSheetsClient` is a strong local test seam, but it still depends on hand-built grids. CoreXLSX could let tests load exported workbook tabs so parser/layout tests start from more realistic evidence.

The stronger first move is not CoreXLSX. It is checked-in, redacted `SheetSnapshot` JSON captured from the Google Sheets API shape the app actually consumes: formatted values plus row visibility metadata. That evidence maps directly to hidden rows, filters, formatted values, and write targeting.

### Before

```swift
let snapshot = SheetSnapshot(values: SheetGridFixture.block27)
let parsed = SheetParser().parse(snapshot: snapshot, tabName: "Block 27")
```

### After

```swift
let workbook = try XLSXFile(filepath: fixturePath)
let snapshot = try SheetSnapshot(xlsx: workbook, sheetName: "Block 27")
let parsed = SheetParser().parse(snapshot: snapshot, tabName: "Block 27")
```

### Why This Is Elegant

It improves evidence quality without touching production code. The app has repeatedly needed workbook-backed verification for Sheet semantics; test-only XLSX loading could reduce translation errors in fixtures.

### Risks

- CoreXLSX is read-oriented; it does not replace the local write simulator.
- XLSX export metadata may not match Google Sheets API metadata for hidden rows, filtered rows, or formatted values.
- If tests start relying on large binary fixtures, review diffs get worse.

### Recommendation

Do not add CoreXLSX first. Add API-captured `SheetSnapshot` fixtures first. Consider CoreXLSX only as a supplemental import path for human-exported workbook evidence, and keep `LocalWorkbookSheetsClient` as the write-path simulator.

## 8. Separate Future Issue: Swift Charts For Performance History

Source:

- Apple, [Swift Charts](https://developer.apple.com/documentation/Charts)

### Why It May Fit

`CONTEXT.md` defines Performance History as a user-facing historical view of prior logged performances. When that feature becomes richer, the app should use Swift Charts instead of drawing custom chart geometry.

### Before

```swift
GeometryReader { proxy in
    Path { path in
        // hand-built line chart math
    }
}
```

### After

```swift
Chart(history) { entry in
    LineMark(
        x: .value("Session", entry.sessionOrder),
        y: .value("Weight", entry.weight)
    )
}
```

### Why This Is Elegant

Charts are platform-native, SwiftUI-native, and more likely to pick up system accessibility and visual behavior correctly on iOS 26. This is a future feature recommendation, not a current refactor.

## 9. Defer Swift OpenAPI Generator And The Google REST Client

Sources:

- Apple, [`swift-openapi-generator`](https://github.com/apple/swift-openapi-generator)
- Swift.org, [Introducing Swift OpenAPI Generator](https://www.swift.org/blog/introducing-swift-openapi-generator/)
- Google, [Google APIs Client Library for Objective-C for REST](https://github.com/google/google-api-objectivec-client-for-rest)
- Google, [Access Google APIs in an iOS app](https://developers.google.com/identity/sign-in/ios/api-access)

### Why It Is Attractive

Swift OpenAPI Generator creates type-safe clients from OpenAPI documents at build time. It supports generated iOS client code and URLSession transport, and the official README lists generated code/runtime support for iOS 13+.

Google's REST client is also credible: Google describes it as the recommended library for JSON-based Google APIs on Apple platforms, and Google Sign-In can provide access tokens or a fetcher authorizer for the API client.

### Why It Is Not First

The app's Google Sheets risk is not mostly HTTP ceremony. The hard part is domain interpretation:

- dynamic Sheet layout
- hidden rows
- Coach Notes vs Legacy Logs
- Visible Writable Row selection
- pending write conflict behavior
- Last Set RPE targeting

`GoogleSheetsClient` is currently small and testable through `SheetsClient`. A generated client or Google's Objective-C-shaped client could reduce DTO/request code, but it would not remove the domain complexity that has caused the most defects.

The Google REST client also adds risks specific to this app:

- Objective-C API shape in a Swift concurrency codebase.
- Async bridging.
- Additional dependency weight.
- Possible loss of tight control over `fields`, `includeGridData`, formatted values, and row visibility metadata.

### Before

```swift
var req = URLRequest(url: url)
req.httpMethod = "POST"
req.setValue("Bearer \(try await tokenProvider())", forHTTPHeaderField: "Authorization")
req.httpBody = try JSONEncoder().encode(body)
```

### After

```swift
let response = try await client.batchUpdateValues(
    .init(path: .init(spreadsheetId: spreadsheetId), body: .json(body))
)
```

### Recommendation

Defer until one of these becomes true:

- The Google client grows beyond its current small request set.
- We can pin an OpenAPI spec for exactly the Sheets/Drive subset we use.
- The generated DTOs can be isolated behind the existing `SheetsClient` seam.

## 10. Defer TCA And `swift-navigation`

Sources:

- Point-Free, [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture)
- Point-Free, [`swift-navigation`](https://github.com/pointfreeco/swift-navigation)

### Why They Are Attractive

TCA solves state management, composition, side effects, and testing for complex apps. Its README states it can be used with SwiftUI and across Apple platforms. `swift-navigation` can make navigation state explicit and testable.

### Why They Are Not First

WorkoutTracker already has focused modules:

- `WorkoutStore`
- `SyncCoordinator`
- `SessionCoordinator`
- `SessionProgressTracker`
- presentation-state modules under `WorkoutTracker/Progress`

A wholesale TCA migration would touch nearly every screen and store before proving user value. That is a poor first move for a codebase whose biggest complexity is the Sheet-as-backend contract.

### Better Before/After

Before:

```swift
NavigationStack {
    SessionView(...)
        .navigationDestination(isPresented: blockOverviewRequestBinding) {
            BlockOverviewView(...)
        }
}
```

After, if navigation becomes painful:

```swift
@Observable
final class AppRouter {
    var path: [Route] = []
    var sheet: AppSheet?
}
```

This can be done internally before adopting `swift-navigation`. If route modeling gets bigger, revisit the package.

## 11. Avoid Third-Party Liquid Glass Kits For Now

Sources:

- [`muhittincamdali/LiquidGlassKit`](https://github.com/muhittincamdali/LiquidGlassKit)
- [`DnV1eX/LiquidGlassKit`](https://github.com/DnV1eX/LiquidGlassKit)

### Why They Are Tempting

They advertise iOS 26 Liquid Glass components, backports, or deeper customization.

### Why They Are Risky Here

- The app already targets iOS 26, so backports are not useful.
- Apple owns the visual material and can tune it across iOS 26.x.
- At least one Liquid Glass kit documents custom Metal/private-class-inspired behavior and an App Store-safe fallback that is more CPU-intensive.
- Mature app-specific Liquid Glass design is more likely to come from native SwiftUI plus repo-owned theme primitives than from a young component kit.

### Recommendation

Do not adopt. Use these projects only as inspiration for patterns to avoid or for prototype-only comparison.

## Other Libraries Considered

| Library/framework | Decision | Reason |
| --- | --- | --- |
| Alamofire | Avoid | Current HTTP surface is small; `URLSession` plus `SheetsClient` is enough. |
| Kingfisher / SDWebImage | Avoid | No meaningful remote-image workflow in the current app. |
| GRDB | Defer | SwiftData is already the local cache; consider GRDB only if SwiftData creates measurable reliability/performance problems. |
| ViewInspector | Defer/Avoid | Component tests already assert presentation contracts without introspecting SwiftUI internals. |
| `swift-parsing` | Speculative | Could help formal text parsers, but current pain is Sheet layout semantics more than parser combinator syntax. |
| Async Algorithms | Speculative | Useful if sync streams or event debouncing become central; not justified for current code. |
| App Intents | Future feature | Good for “start rest timer,” “log current set,” or “open Current Session” system actions, but not a reuse cleanup. |

## Proposed Adoption Plan

### Phase 1: Dependency Pilot

Add `swift-dependencies` and convert one narrow timing/defaults slice.

Recommended slice:

- `RestTimer`
- `RestPillView`
- affected `SessionCoordinator`/rest timer tests

Verify:

- `swift test`
- existing rest timer and session coordinator tests
- no View/Theme changes unless required

Decision gate:

- Keep only if tests become simpler and initializer seams shrink.

### Phase 2: Internal Liquid Glass Primitive

Add one internal helper for card glass surfaces, then migrate only the duplicated call sites that already match the same shape.

Verify:

- `swift test` for presentation tests if state helpers change.
- Xcode build because Views are excluded from `Package.swift`.
- Ralph/screenshot check because View/Theme changes are visual.

Decision gate:

- Keep only if the helper reduces repeated Liquid Glass decisions without hiding layout.

### Phase 3: Hold Snapshot Testing Until Ralph Misses A Repeated Regression

Do not add `swift-snapshot-testing` now. Keep Ralph screenshots as the visual gate.

Reopen this only when:

- A repeated visual regression reaches review despite Ralph screenshots, or
- Ralph screenshot evidence becomes too hard to compare manually.

Future verify:

- Xcode-hosted snapshot target on the agreed simulator/runtime.
- CI/Ralph expectations documented before expanding.
- Failures produce actionable diffs and churn stays low.

### Phase 4: Opportunistic Collections/Algorithms

Do not add these preemptively. During future parser/progression work, allow Apple `swift-collections` or `swift-algorithms` if the change removes repeated ordering/uniqueness/indexing invariants.

Verify:

- Unit tests around the domain interface, not the collection implementation.

### Phase 5: Separate Product/System Issues

Explore BackgroundTasks, ActivityKit, and Swift Charts as separate proposals/issues, not as part of the dependency pilot.

BackgroundTasks first slice:

- Register a diagnostic app refresh task.
- Prove background launch can read configuration safely.
- Do not flush real pending writes until diagnostics pass.

ActivityKit first slice:

- Model `RestActivityAttributes`.
- Add a widget extension with one countdown view.
- Start/end the Live Activity from `RestTimer` or a small adapter.
- Keep the in-app Liquid Glass pill as the primary control surface.

Swift Charts first slice:

- Wait until Performance History needs visualization.
- Use native `Chart` marks rather than custom drawing.
- Keep chart inputs as presentation models derived from Last Performed / Performance History data.

## Top Recommendation

Start with `swift-dependencies` in the rest timer slice.

It is the most likely to reduce hand-written infrastructure without causing broad architecture churn. It also tests the core question behind this proposal: can a package make our modules deeper and tests clearer while preserving the Sheet-first domain model?

If that pilot succeeds, the second move should be an internal native Liquid Glass primitive. That keeps the app visually modern without outsourcing the design system to a young third-party package.

The strongest system-framework follow-up is ActivityKit for the rest timer, because it improves the athlete experience directly. The strongest sync-quality follow-up is BackgroundTasks, but only after a diagnostic slice proves background auth/config behavior on device or simulator. Both should be separate issues, not riders on a dependency cleanup PR.

## Decision Checklist

Use this checklist before adopting any package:

- Does the first adoption PR delete or materially simplify enough app-owned code to justify the package?
- Does it remove repeated app code, or only move it behind unfamiliar syntax?
- Does it deepen a real module interface?
- Can the dependency stay behind one app-owned seam?
- Does it support Swift 6 and modern Apple platforms without blocking iOS 26?
- For UI code, does it preserve native Liquid Glass behavior?
- Can we prove the adoption with a narrow test slice?
- Can we revert the pilot without a cross-app migration?
