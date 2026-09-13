# Headless SwiftPM executable over the library: host toolchain floor

Wayfinder ticket #520 · 2026-09-13 · Research, primary sources only.
Scope: documented facts about running the `WorkoutTracker` SPM library (SwiftData +
`@Observable` + Swift 6 strict concurrency) from a macOS command-line `executableTarget`.
**This document records findings only; anything not documented is marked "measure in #530".**
No Swift toolchain was available while writing; nothing here was compiled.

Terminology follows `CONTEXT.md`: Block, Session, Set Log, Current Session.

---

## 1. Toolchain and OS floor

### 1.1 Framework availability (macOS deployment target)

| Framework / symbol | Minimum macOS | Source |
|---|---|---|
| SwiftData (`ModelContainer`, `ModelConfiguration`, `ModelContext`) | 14.0 (Swift 5.9+) | Apple, [SwiftData](https://developer.apple.com/documentation/swiftdata), [ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer) availability tables |
| SwiftData `DefaultStore` (the Core Data-backed store) | 15.0 | Apple, [DefaultStore](https://developer.apple.com/documentation/swiftdata/defaultstore) |
| Observation / `@Observable` | 14.0 | Apple, [Observation](https://developer.apple.com/documentation/observation), [Observable()](https://developer.apple.com/documentation/observation/observable()) |
| SwiftUI | 10.15 | Apple, [SwiftUI](https://developer.apple.com/documentation/swiftui) |

- The only platforms listed for SwiftData and Observation are iOS, iPadOS, Mac Catalyst,
  macOS, tvOS, visionOS, watchOS — no Linux (same availability tables).
- `platforms: [.macOS(.v15), .iOS(.v18)]` (`Package.swift:6`) is therefore **sufficient**:
  it exceeds every framework floor above, including `DefaultStore` (macOS 15). The
  `platforms` value is a deployment target, not a build-host restriction: "By default,
  Swift Package Manager assigns a predefined minimum deployment version for each supported
  platforms unless you configure supported platforms using the `platforms` API"
  (Apple, [SupportedPlatform](https://developer.apple.com/documentation/packagedescription/supportedplatform)).
- No `#available`/`@available` gates exist in the library sources outside `Views/`
  (grep of `WorkoutTracker/`), so nothing in the library demands newer than macOS 15.

### 1.2 Host Xcode / compiler

- Swift 6 language mode is selected by the manifest: `// swift-tools-version:6.0`
  (`Package.swift:1`). SwiftPM maps tools version major > 5 to language version 6:
  `default: return .v6` in `ToolsVersion.swiftLanguageVersion`
  ([swift-package-manager `Sources/PackageModel/ToolsVersion.swift`](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageModel/ToolsVersion.swift)).
  SE-0435 records the design: language version is "determined based on the tools version"
  when not set explicitly ([SE-0435](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0435-swiftpm-per-target-swift-language-version-setting.md)).
  Swift 6 mode "turns on strict concurrency by default" (same proposal, Motivation).
- The tools version "declares the minimum version of the Swift compiler required to use the
  package" (swift.org, [Setting the Swift tools version](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/settingswifttoolsversion)),
  so the compiler floor is Swift 6.0.
- Xcode bundles: Xcode 16 → Swift 6.0, requires macOS 14.5+, ships macOS 15 SDK;
  Xcode 26 → Swift 6.2, requires macOS 15.6+; Xcode 27 RC → Swift 6.4, requires
  macOS 26.6+ (Apple, [Xcode support / version table](https://developer.apple.com/support/xcode/)).
- Repo constraint that dominates: CI runs `swift test` and the app build on the `xcode-27`
  runner (`.github/workflows/ci.yml`, jobs `swift-tests`, `app-build`), and the header comment
  says Liquid Glass APIs (ADR-0004) need Xcode 27. A CLI target added to `Package.swift`
  will be built by that same job, so the **practical floor is whatever `xcode-27` is —
  Xcode 27 RC on macOS 26.6+** — even though the documented framework floor is lower.
- The Xcode app target already sets `SWIFT_STRICT_CONCURRENCY = complete`
  (`WorkoutTracker.xcodeproj/project.pbxproj:929`), and `swift test` compiles the library in
  Swift 6 mode today, so the library already passes strict checking on a macOS host.

### 1.3 `import SwiftUI` in the library on a macOS executable

- `Theme.swift` is the only library file importing SwiftUI (`WorkoutTracker/Theme.swift:2`);
  UIKit/CoreText use is fenced by `#if canImport(UIKit)` (lines 4-7, 834, 855) with an
  explicit macOS fallback ("Fonts aren't registered off-device (unit tests on macOS)",
  line 838-840).
- SwiftUI is available on macOS 10.15+ as a linkable framework (§1.1); an executable does
  not need an app bundle to link it. Direct evidence that the file already compiles and links
  in a non-app macOS process: the `swift-tests` CI job runs `swift test` on a macOS runner
  against the library target that includes `Theme.swift` (`Package.swift:8-21` excludes only
  `Views`, `LiveActivity`, assets, fonts, `GoogleAuth.swift`, `WorkoutTrackerApp.swift`),
  so the test bundle — a headless macOS process — links the module today.
- Whether *evaluating* `Theme.font(...)` from a CLI (no registered fonts, no run loop)
  behaves is not documented; **measure in #530** if the CLI ever touches `Theme`.

---

## 2. Entry point, main actor, and the stores

### 2.1 `@main` with `static func main() async`

- The `@main` type "must provide a `main` type function that doesn't take any arguments and
  returns `Void`", and may `throws` (Swift book, [Attributes → main](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/attributes#main)).
- Async form: "A program can use `@main` with a `main()` function that is `async` …
  Semantically, Swift will create a new task that will execute `main()`. Once that task
  completes, the program terminates." ([SE-0304](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0304-structured-concurrency.md), "Asynchronous programs").
- Main-thread guarantee: "like the other entrypoints, top-level code runs on the main
  thread, so we can make the top-level code space implicitly main-actor isolated"
  ([SE-0343](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0343-top-level-concurrency.md)).
  A `@MainActor static func main() async` on the `@main` type is therefore the documented way
  to construct and drive the library's `@MainActor @Observable` stores
  (`Stores/WorkoutStore.swift:15-16`, `Stores/SyncCoordinator.swift:4-5`) without hopping
  actors. This mirrors what the app does: it builds the container and stores in the `App`
  initializer, which is main-actor code (`WorkoutTrackerApp.swift:46-62`).
- Observation itself needs no run loop or UI: `withObservationTracking` is a plain function
  (Apple, [Observation](https://developer.apple.com/documentation/observation)). Whether a
  one-shot CLI that calls store methods and then exits sees every `onChange` is not
  documented — a one-shot CLI does not need it; **measure in #530** only if the CLI is
  expected to observe changes rather than read state after awaiting a call.
- If swift-argument-parser is used: `AsyncParsableCommand` supplies its own
  `public static func main() async` and carries **no** `@MainActor` annotation
  ([`AsyncParsableCommand.swift`](https://github.com/apple/swift-argument-parser/blob/main/Sources/ArgumentParser/Parsable%20Types/AsyncParsableCommand.swift)),
  so `run()` is nonisolated; the CLI must `await MainActor.run { … }` (or call into a
  `@MainActor` helper) before touching the stores. Still runs on the process main thread
  per SE-0343, but the compiler will not treat `run()` as isolated.

### 2.2 `ModelContainer` in a process without an app bundle

- Creating a container without SwiftUI is documented:
  "If you're not using SwiftUI, create a model container manually using the appropriate
  initializer: `let container = try ModelContainer([Trip.self, Accommodation.self])`"
  (Apple, [Preserving your app's model data across launches](https://developer.apple.com/documentation/swiftdata/preserving-your-apps-model-data-across-launches)).
  The app does exactly this (`WorkoutTrackerApp.swift:46-48`).
- `mainContext` is declared `@MainActor var mainContext: ModelContext { get }`
  (Apple, [mainContext](https://developer.apple.com/documentation/swiftdata/modelcontainer/maincontext)),
  and "SwiftData automatically sets [`autosaveEnabled`] to `true` for the model container's
  `mainContext`"; manually created contexts default to `false`
  (Apple, [autosaveEnabled](https://developer.apple.com/documentation/swiftdata/modelcontext/autosaveenabled)).
  A one-shot CLI must not rely on autosave's "various times during the lifecycle of windows,
  scenes, views" — call `save()` explicitly before exit.
- `ModelContainer` conforms to `Sendable`; `ModelContext` does not (only `Equatable`,
  `SendableMetatype`) (Apple, ModelContainer / [ModelContext](https://developer.apple.com/documentation/swiftdata/modelcontext) relationship sections).
- **Default store location is not documented.** With an empty configurations array "the
  framework creates an instance of `ModelConfiguration` for you by combining your app's
  entitlements with the type's default values"
  (Apple, [init(for:migrationPlan:configurations:)](https://developer.apple.com/documentation/swiftdata/modelcontainer/init(for:migrationplan:configurations:)-1czix)).
  What "default values" resolve to for an unsandboxed, unbundled executable is unspecified;
  **measure in #530**. Do not depend on it — pass an explicit location.
- Explicit location: `init(_ name: String? = nil, schema: Schema? = nil, url: URL,
  allowsSave: Bool = true, cloudKitDatabase: … = .automatic)` where `url` is "The on-disk
  location of the schema's persistent storage"
  (Apple, [init(_:schema:url:allowsSave:cloudKitDatabase:)](https://developer.apple.com/documentation/swiftdata/modelconfiguration/init(_:schema:url:allowssave:cloudkitdatabase:))).
- Ephemeral: `ModelConfiguration(isStoredInMemoryOnly: true)` — "whether the associated
  persistent storage is ephemeral and exists only in memory"
  (Apple, [init(isStoredInMemoryOnly:)](https://developer.apple.com/documentation/swiftdata/modelconfiguration/init(isstoredinmemoryonly:))).
  The repo's fixture path already uses this (`Fixtures/UITestFixture.swift:88`).

---

## 3. Persistence across one-shot CLI invocations

- Nothing in SwiftData's documentation forbids reopening a `url:`-configured store from a
  new process; the `url` initializer exists precisely to name an on-disk file (§2.2).
  `DefaultStore` is "A data store that uses Core Data as its underlying storage mechanism"
  (Apple, [DefaultStore](https://developer.apple.com/documentation/swiftdata/defaultstore)).
- Core Data documents multi-process stores explicitly:
  `NSPersistentStoreRemoteChangeNotificationPostOptionKey` — "a persistent store posts a
  remote change notification for every write to the store, including writes by other
  processes" (Apple, [NSPersistentStoreRemoteChangeNotificationPostOptionKey](https://developer.apple.com/documentation/coredata/nspersistentstoreremotechangenotificationpostoptionkey)).
  Sequential (non-overlapping) one-shot processes are the easy case of this; SwiftData
  exposes no locking API, and Apple does not document SQLite lock or journal-mode behaviour
  for SwiftData (`NSSQLitePragmasOption` discussion covers only `fullfsync`/`synchronous`,
  [Apple](https://developer.apple.com/documentation/coredata/nssqlitepragmasoption)).
  Concurrent CLI runs against one store: **measure in #530** or simply serialise them.
- Schema evolution: "As your app's schema evolves, the container performs automatic
  migrations of the persisted model data … If the aggregate changes between two versions of
  your schema exceed the capabilities of automatic migrations, provide the container with a
  [`SchemaMigrationPlan`]" (Apple, [ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer)).
  Plans are built from `VersionedSchema` (`versionIdentifier`, `models`) and
  `MigrationStage.lightweight(fromVersion:toVersion:)` /
  `.custom(fromVersion:toVersion:willMigrate:didMigrate:)`
  (Apple, [VersionedSchema](https://developer.apple.com/documentation/swiftdata/versionedschema),
  [MigrationStage](https://developer.apple.com/documentation/swiftdata/migrationstage)).
- The app today uses no `VersionedSchema` or migration plan
  (`WorkoutTrackerApp.swift:46-48`), so any CLI store in a temp dir is only as durable as
  automatic migration across code changes. Gotcha for the spike: a store written by one
  build and reopened by a build whose `@Model` types changed non-lightweight-ly will fail to
  open; the cheap mitigation is a fresh temp dir per test run (or `deleteAllData()` /
  `erase()`, listed under ModelContainer's instance methods).

---

## 4. `#if DEBUG` fixtures and build configuration

- Both fixture files are whole-file `#if DEBUG` (`Fixtures/UITestFixture.swift:1`,
  `Fixtures/WorkoutFixtureScenarios.swift:1`).
- "Package manager supports two general build configurations: Debug (default) and Release.
  By default, running `swift build` builds the package using its debug configuration"; use
  `swift build -c release` for release (swift.org, [Using build configurations](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/usingbuildconfigurations)).
  `swift run` takes the same `--configuration` option (swift.org, [swift run](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/swiftrun)).
- The `DEBUG` condition is added only for the debug configuration:
  `case .debug: compilationConditions += ["-DDEBUG"]` / `case .release: break`
  ([swift-package-manager `SwiftModuleBuildDescription.swift`](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/Build/BuildDescription/SwiftModuleBuildDescription.swift)).
  Consequence: `swift run` (debug) sees `UITestFixture` and `WorkoutFixtureScenarios`;
  `swift run -c release` compiles the library **without** them, so a CLI that references
  fixture types must itself be `#if DEBUG`-fenced or must define its own condition via
  `swiftSettings: [.define("…")]` (target-specific flags are documented in the same
  build-configurations article).

---

## 5. swift-argument-parser

- Current release: **1.8.2, 2026-06-04**; 1.8.1 on 2026-05-27; 1.8.0 on 2026-05-25
  ([CHANGELOG.md](https://github.com/apple/swift-argument-parser/blob/main/CHANGELOG.md)).
- Swift 6: since 1.8.0 "The minimum Swift version for `swift-argument-parser` has been
  updated to Swift 6. Users of older Swift versions can continue using version 1.7.1"
  (same CHANGELOG, #882); the manifest is `// swift-tools-version:6.0`
  ([Package.swift](https://github.com/apple/swift-argument-parser/blob/main/Package.swift)).
  Concurrency: `CommandConfiguration` is `Sendable` (#615); property wrappers conditionally
  conform to `Sendable`; `ParsableArguments`/`ExpressibleByArgument` conform to
  `SendableMetatype` on Swift 6.2+ (#789) (CHANGELOG).
- Async entry: `AsyncParsableCommand` with `mutating func run() async throws`; the async
  parse APIs are `asyncParse()` / `asyncParseAsRoot()` since 1.8.1 (CHANGELOG #908).
- JSON: the only JSON facility is `--experimental-dump-help`, which "Dumps
  command/argument/help information as JSON" — a description of the *command tree*, not a
  JSON output mode for results, and "Features prefixed with `--experimental` are not
  considered stable" ([ExperimentalFeatures.md](https://github.com/apple/swift-argument-parser/blob/main/Sources/ArgumentParser/Documentation.docc/Articles/ExperimentalFeatures.md)).
  Result serialisation is the CLI's own job (`JSONEncoder` from Foundation).

---

## 6. Cost profile

- No first-party (Apple or swift.org) figures exist for incremental `swift build` time or
  process launch time of a small SwiftPM executable on Apple Silicon; the SwiftPM
  documentation describes only the flags each configuration uses (`-Onone -g
  -enable-testing` for debug; `-O -whole-module-optimization` for release,
  [Using build configurations](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/usingbuildconfigurations)).
  **Measure in #530**: (a) no-op `swift build` after a one-line edit in `Stores/`,
  (b) `swift run` wall time for `--help`, (c) wall time to open a `url:` store and fetch
  one `Block`, debug vs `-c release`.

---

## 7. Linux

- Off the table for this executable. SwiftData is listed only for Apple platforms (§1.1
  availability table) and the library's models are `@Model` classes throughout
  (`Models/Block.swift`, `Models/Exercise.swift`, `Models/PendingWrite.swift`,
  `Models/LastPerformedEntry.swift`).
- Observation, by contrast, *is* cross-platform: it ships in the Swift toolchain as
  `swiftObservation` with Linux/Android/Windows module dependencies declared
  ([swift `stdlib/public/Observation/Sources/Observation/CMakeLists.txt`](https://github.com/swiftlang/swift/blob/main/stdlib/public/Observation/Sources/Observation/CMakeLists.txt)),
  and SE-0395 places it "in a module that is part of the Swift language but outside of the
  standard library" ([SE-0395](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0395-observability.md)).
  So Observation is not the blocker; SwiftData (and SwiftUI in `Theme.swift`) is.

---

## Verdict

The documented floor is comfortably below what the repo already requires: SwiftData,
Observation and SwiftUI all exist on macOS 14–15, `platforms: [.macOS(.v15), .iOS(.v18)]`
clears every one of them including `DefaultStore`, and the library already compiles and
links (SwiftUI import included) as a headless macOS process under `swift test` on the
`xcode-27` runner, so the effective toolchain for a CLI `executableTarget` is the same
Xcode 27 / Swift 6.4 / macOS 26.6+ the CI already pins, with Swift 6 language mode and
strict concurrency coming for free from `swift-tools-version:6.0`. A `@main` type with
`@MainActor static func main() async` runs on the main thread by SE-0304/0343 and can
construct the `@MainActor @Observable` stores exactly as `WorkoutTrackerApp` does; the
container must be given an explicit `ModelConfiguration(url:)` (default location for a
bundle-less process is undocumented) and `save()` must be called explicitly because
`mainContext` autosave is tied to scene lifecycle. Reopening that on-disk store from
successive one-shot runs is within Core Data's documented multi-process support, but the
app has no `VersionedSchema`, so use a fresh temp dir per run or accept automatic-migration
failures across model edits. `swift run` defaults to debug and defines `DEBUG`, so the
fixtures are visible there and vanish under `-c release`. swift-argument-parser 1.8.2
requires Swift 6, offers async commands, and has no JSON result output (only the
experimental help dump). Linux is excluded by SwiftData's Apple-only availability, not by
Observation. Build/launch timings have no first-party numbers and must be measured in #530.
