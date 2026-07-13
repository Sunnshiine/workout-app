# Workout App — Agent Guide

A mobile client for powerlifting athletes that surfaces and logs workouts from a
coach-managed Google Sheet. The Sheet is the single source of truth; the app is a
read-write client with a local cache (ADR-0001).

## Build, Test & Run

Scheme is `WorkoutTracker` for all runs; default simulator is `iPhone 17 Pro`.

```bash
# Fast unit + component tests (no Secrets.xcconfig needed)
swift test

# Unit + component tests via Xcode
xcodebuild test -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WorkoutTrackerTests

# UI integration tests
xcodebuild test -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:WorkoutTrackerUITests

# Build & run on the simulator
xcodebuild build -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

- The `WorkoutTracker` scheme launches with `-UITEST_FIXTURE true` and
  `-UITEST_SESSION true` — it runs against deterministic local fixtures, **not**
  the live Google Sheet. To run against live data, use the `Copy of WorkoutTracker` scheme (`-UITEST_FIXTURE false`).
- Concurrent UI-test sessions must not share the same simulator. Use distinct
  simulator UDIDs with `-destination 'platform=iOS Simulator,id=<UDID>'` and
  isolated `-derivedDataPath` / `-clonedSourcePackagesDirPath` values.
- Prefer XcodeBuildMCP for build/run/test on the simulator. If using XcodeBuildMCP,
  use the installed XcodeBuildMCP skill before calling XcodeBuildMCP tools.
- If XcodeBuildMCP accessibility snapshots return an empty AXApplication, reboot
  the simulator before diagnosing app code.
- For target-specific UI gates, prefer raw `xcodebuild ... -only-testing:WorkoutTrackerUITests`
  or verify the output actually ran `WorkoutTrackerUITests`.

## Linting & Formatting

- **SwiftLint** runs automatically via the `SwiftLintPlugins` build tool plugin (wired through the Xcode project, not `Package.swift`). Config: `.swiftlint.yml`.
- **swift-format** is installed via Homebrew. Config: `.swift-format`. Run manually: `swift-format -i -r WorkoutTracker/ WorkoutTrackerTests/`
- Do not run `swiftlint --fix` in build phases — run it manually when needed.

## Git Worktrees

`Secrets.xcconfig` is git-ignored but required for Xcode app-target builds. New
git worktrees should receive it automatically from the tracked post-checkout
hook once the bootstrap is installed:

```bash
scripts/install-worktree-bootstrap.sh --source /path/to/private/Secrets.xcconfig
```

The installer sets `core.hooksPath=.githooks`, records the trusted source when
`--source` is provided, and backfills existing worktrees. The bootstrap source
order is: `SECRETS_XCCONFIG_SOURCE`, `git config workout.secretsXcconfigSource`,
the `main` worktree's `Secrets.xcconfig`, then `Secrets.xcconfig.template` as a
build-only fallback. `swift test` does not require it; only Xcode app-target
builds do.

XcodeBuildMCP session defaults point at the main project path and do not apply inside a worktree. Pass `-project <worktree-path>/WorkoutTracker.xcodeproj` explicitly when calling xcodebuild from a worktree.

## Architecture

A navigation map; see `CONTEXT.md` for the domain glossary and `docs/adr/` for decisions.

```text
WorkoutTracker/
├── WorkoutTrackerApp.swift     App entry point (@main)
├── Models/                     Domain types (Block, Week, Session, Exercise, Set …)
├── Parsing/                    Sheet → domain interpretation (layout interpreter)
├── Sheets/                     Google Sheets client + auth (GoogleAuth.swift)
├── Stores/                     Local cache, sync coordination & persisted state
├── Progress/                   Session/Week progression (Current Session, Move On, Open Exercises, Supersets)
├── LoadSuggestionEngine.swift  Load Suggestion calculations
├── Theme.swift                 Liquid Glass design system (ADR-0004)
├── Views/                      SwiftUI views (excluded from the SPM library target)
└── Fixtures/                   UI-test fixture data (-UITEST_FIXTURE)

Tests/  →  Unit/ · Component/ · UI/ · Support/
```

## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues for `Sunnshiine/workout-app`. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default five-label triage vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repo: read root `CONTEXT.md` for domain language and root `docs/adr/` for decisions. For product or UI work, also read `PRODUCT.md` and `DESIGN.md`. See `docs/agents/domain.md`.

## Swift Coding Style

This section applies when working on `**/*.swift` and `**/Package.swift`.

### Formatting

- **SwiftFormat** for auto-formatting, **SwiftLint** for style enforcement
- `swift-format` is bundled with Xcode 16+ as an alternative

### Immutability

- Prefer `let` over `var` — define everything as `let` and only change to `var` if the compiler requires it
- Use `struct` with value semantics by default; use `class` only when identity or reference semantics are needed

### Naming

Follow [Apple API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/):

- Clarity at the point of use — omit needless words
- Name methods and properties for their roles, not their types
- Use `static let` for constants over global constants

### Error Handling

Use typed throws (Swift 6+) and pattern matching:

```swift
func load(id: String) throws(LoadError) -> Item {
    guard let data = try? read(from: path) else {
        throw .fileNotFound(id)
    }
    return try decode(data)
}
```

### Concurrency

Enable Swift 6 strict concurrency checking. Prefer:

- `Sendable` value types for data crossing isolation boundaries
- Actors for shared mutable state
- Structured concurrency (`async let`, `TaskGroup`) over unstructured `Task {}`

## Swift Testing

This section applies when working on `**/*.swift` and `**/Package.swift`.

### Framework

Use **Swift Testing** (`import Testing`) for new tests. Use `@Test` and `#expect`:

```swift
@Test("User creation validates email")
func userCreationValidatesEmail() throws {
    #expect(throws: ValidationError.invalidEmail) {
        try User(email: "not-an-email")
    }
}
```

### Test Isolation

Each test gets a fresh instance — set up in `init`, tear down in `deinit`. No shared mutable state between tests.

### Parameterized Tests

```swift
@Test("Validates formats", arguments: ["json", "xml", "csv"])
func validatesFormat(format: String) throws {
    let parser = try Parser(format: format)
    #expect(parser.isValid)
}
```

### Coverage

```bash
swift test --enable-code-coverage
```

### Reference

See skill: `swift-protocol-di-testing` for protocol-based dependency injection and mock patterns with Swift Testing.

## Swift Patterns

This section applies when working on `**/*.swift` and `**/Package.swift`.

### Protocol-Oriented Design

Define small, focused protocols. Use protocol extensions for shared defaults:

```swift
protocol Repository: Sendable {
    associatedtype Item: Identifiable & Sendable
    func find(by id: Item.ID) async throws -> Item?
    func save(_ item: Item) async throws
}
```

### Value Types

- Use structs for data transfer objects and models
- Use enums with associated values to model distinct states:

```swift
enum LoadState<T: Sendable>: Sendable {
    case idle
    case loading
    case loaded(T)
    case failed(Error)
}
```

### Actor Pattern

Use actors for shared mutable state instead of locks or dispatch queues:

```swift
actor Cache<Key: Hashable & Sendable, Value: Sendable> {
    private var storage: [Key: Value] = [:]

    func get(_ key: Key) -> Value? { storage[key] }
    func set(_ key: Key, value: Value) { storage[key] = value }
}
```

### Dependency Injection

Inject protocols with default parameters — production uses defaults, tests inject mocks:

```swift
struct UserService {
    private let repository: any UserRepository

    init(repository: any UserRepository = DefaultUserRepository()) {
        self.repository = repository
    }
}
```

### References

See skill: `swift-actor-persistence` for actor-based persistence patterns.
See skill: `swift-protocol-di-testing` for protocol-based DI and testing.

## Swift Hooks

This section applies when working on `**/*.swift` and `**/Package.swift`.

### Post-edit Checks

Some agent harnesses (e.g. Codex) don't run the `~/.claude/settings.json` hooks that automate these. If yours doesn't, run them manually after editing Swift files:

- **SwiftFormat**: Auto-format `.swift` files after edit
- **SwiftLint**: Run lint checks after editing `.swift` files
- **swift build**: Type-check modified packages after edit

### Warning

Flag `print()` statements — use `os.Logger` or structured logging instead for production code.

## Swift Security

This section applies when working on `**/*.swift` and `**/Package.swift`.

### Secret Management

- Use **Keychain Services** for sensitive data (tokens, passwords, keys) — never `UserDefaults`
- Use environment variables or `.xcconfig` files for build-time secrets
- Never hardcode secrets in source — decompilation tools extract them trivially

```swift
let apiKey = ProcessInfo.processInfo.environment["API_KEY"]
guard let apiKey, !apiKey.isEmpty else {
    fatalError("API_KEY not configured")
}
```

### Transport Security

- App Transport Security (ATS) is enforced by default — do not disable it
- Use certificate pinning for critical endpoints
- Validate all server certificates

### Input Validation

- Sanitize all user input before display to prevent injection
- Use `URL(string:)` with validation rather than force-unwrapping
- Validate data from external sources (APIs, deep links, pasteboard) before processing
