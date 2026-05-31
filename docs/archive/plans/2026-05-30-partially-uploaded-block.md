# Partially Uploaded Block Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the athlete view and log any populated (Available) Session in a partially-uploaded Block while rendering the coach's not-yet-uploaded (Unavailable) Sessions as distinct, inert tiles in the 4×4 Block grid.

**Architecture:** Availability is *derived* per Session (`!session.exercises.isEmpty`) — nothing is persisted. A new `SessionTileState.unavailable` flows from `SessionProgressTracker` through `BlockOverviewPresentation` into a recessed, non-interactive `SessionTile`. Current Session derivation gains an "always Available" guard. Move On skips Unavailable Sessions to the next Available one, and — when none remain ahead — fires the celebration then requests programmatic navigation to the Block grid.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Testing (`@Test`/`#expect`), XcodeBuildMCP for UI verification, `ui-screenshot-reviewer` for the tile's visual review. Spec: `docs/superpowers/specs/2026-05-30-partially-uploaded-block-design.md`.

**Before starting:** You are on `main`. Create a feature branch first (e.g. `git checkout -b feat/partially-uploaded-block`). Run the full suite with `swift test`; targeted runs use `swift test --filter <testFunctionName>`.

---

## File Structure

All changes land in existing files — no new files.

- `WorkoutTracker/Progress/SessionProgressTracker.swift` — `SessionTileState.unavailable`; `isAvailable`; `tileState`, `currentSession`, `nextSession` changes; new `hasSessionAhead`.
- `WorkoutTracker/Theme.swift` — Unavailable tile color + opacity constants.
- `WorkoutTracker/Views/SessionTile.swift` — render `.unavailable` (recessed, "Not uploaded").
- `WorkoutTracker/Views/BlockOverviewView.swift` — disable the Button for Unavailable tiles.
- `WorkoutTracker/Stores/WorkoutStore.swift` — `canMoveOn`, `requestMoveOnCelebration`, `advance`, new `pendingBlockOverviewRequest` + `clearBlockOverviewRequest()`.
- `WorkoutTracker/Views/SessionView.swift` — consume `pendingBlockOverviewRequest` → push `BlockOverviewView`.
- `WorkoutTracker/Fixtures/WorkoutFixtureScenarios.swift` — `partiallyUploadedBlock()` fixture.
- `WorkoutTracker/Fixtures/UITestFixture.swift` — `-UITEST_PARTIAL_BLOCK` launch arg + seed branch.
- `Tests/Support/WorkoutScenarios.swift` — `partiallyUploadedBlock()` wrapper + name.
- `Tests/Unit/SessionProgressTrackerTests.swift` — updated + new tracker tests.
- `Tests/Unit/WorkoutStoreTests.swift` — fix all-empty test; new partial-block store tests + helper.
- `Tests/Component/BlockOverviewPresentationTests.swift` — new Unavailable presentation test.

---

## Task 1: `SessionTileState.unavailable` + tracker availability + tile rendering

Adds the new state, makes `tileState` return it for Sessions with no Exercises, and renders/inert-disables the tile. The enum case and every `switch` over it must ship together (Swift exhaustiveness).

**Files:**
- Modify: `WorkoutTracker/Progress/SessionProgressTracker.swift`
- Modify: `WorkoutTracker/Theme.swift`
- Modify: `WorkoutTracker/Views/SessionTile.swift`
- Modify: `WorkoutTracker/Views/BlockOverviewView.swift`
- Test: `Tests/Unit/SessionProgressTrackerTests.swift`

- [ ] **Step 1: Update/add the tracker tests**

In `Tests/Unit/SessionProgressTrackerTests.swift`, replace the test `sessionTileStateHasExactlyThreeCases` (the `#expect(SessionTileState.allCases == [.complete, .current, .incomplete])` test) with:

```swift
@MainActor
@Test func sessionTileStateHasFourCases() {
    #expect(SessionTileState.allCases == [.complete, .current, .incomplete, .unavailable])
}
```

Replace the test `tileStateIsIncompleteWhenNonCurrentSessionHasNoSetProgress` with:

```swift
@MainActor
@Test func tileStateDistinguishesPendingAvailableFromUnavailableSessions() {
    let block = makeBlock()
    let pendingSession = block.weeks[0].sessions[0]
    let unavailableSession = block.weeks[0].sessions[1]
    unavailableSession.exercises = []

    let tracker = SessionProgressTracker()

    #expect(tracker.tileState(for: pendingSession, currentSession: nil) == .incomplete)
    #expect(tracker.tileState(for: unavailableSession, currentSession: nil) == .unavailable)
}

@MainActor
@Test func tileStateIsUnavailableEvenWhenItIsTheCurrentSession() {
    let block = makeBlock()
    let session = block.weeks[0].sessions[0]
    session.exercises = []

    let state = SessionProgressTracker().tileState(for: session, currentSession: session)

    #expect(state == .unavailable)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter sessionTileStateHasFourCases`
Expected: FAIL — compile error, `.unavailable` is not a member of `SessionTileState`.

- [ ] **Step 3: Add the enum case and availability check**

In `WorkoutTracker/Progress/SessionProgressTracker.swift`, change the enum to:

```swift
enum SessionTileState: Equatable, Sendable, CaseIterable {
    case complete
    case current
    case incomplete
    case unavailable

    var accessibilityValue: String {
        switch self {
        case .complete:
            "Complete"
        case .current:
            "Current"
        case .incomplete:
            "Incomplete"
        case .unavailable:
            "Not uploaded"
        }
    }
}
```

Add an availability helper to `SessionProgressTracker` (place it just above `tileState`):

```swift
func isAvailable(_ session: Session) -> Bool { !session.exercises.isEmpty }
```

Change `tileState(for:currentSession:)` so the availability check comes first:

```swift
func tileState(for session: Session, currentSession: Session?) -> SessionTileState {
    if !isAvailable(session) {
        return .unavailable
    }

    let sets = session.exercises.flatMap(\.sets)
    if !sets.isEmpty, sets.allSatisfy({ $0.state == .logged || $0.state == .skipped }) {
        return .complete
    }

    if session.persistentModelID == currentSession?.persistentModelID {
        return .current
    }

    return .incomplete
}
```

- [ ] **Step 4: Add the Unavailable tile rendering**

In `WorkoutTracker/Theme.swift`, add next to the other `sessionTile*` constants:

```swift
static let sessionTileUnavailable = Color(red: 0.025, green: 0.055, blue: 0.045).opacity(0.12)
static let sessionTileUnavailableOpacity: Double = 0.55
```

In `WorkoutTracker/Views/SessionTile.swift`, replace the `body` and `tileContent` and the four style computed properties with:

```swift
var body: some View {
    Group {
        if state == .complete || state == .unavailable {
            tileContent
        } else {
            tileContent
                .glassEffect(.regular, in: .rect(cornerRadius: Theme.sessionTileCornerRadius))
        }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Week \(weekNumber), Day \(dayNumber)")
    .accessibilityValue(state.accessibilityValue)
}

private var tileContent: some View {
    VStack(alignment: .leading, spacing: 6) {
        Text("Week \(weekNumber)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(foregroundStyle.opacity(0.78))

        Text("Day \(dayNumber)")
            .font(.title3.weight(.bold))
            .foregroundStyle(foregroundStyle)

        Spacer(minLength: 0)

        if state == .unavailable {
            Label("Not uploaded", systemImage: "lock.fill")
                .font(.caption2.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(foregroundStyle)
        }
    }
    .frame(maxWidth: .infinity, minHeight: Theme.sessionTileMinHeight, alignment: .topLeading)
    .padding(12)
    .background(backgroundColor, in: .rect(cornerRadius: Theme.sessionTileCornerRadius))
    .overlay {
        RoundedRectangle(cornerRadius: Theme.sessionTileCornerRadius)
            .stroke(borderColor, lineWidth: borderWidth)
    }
    .opacity(state == .unavailable ? Theme.sessionTileUnavailableOpacity : 1)
}

private var backgroundColor: Color {
    switch state {
    case .complete:
        Theme.sessionTileComplete
    case .current, .incomplete:
        Theme.sessionTileIncomplete
    case .unavailable:
        Theme.sessionTileUnavailable
    }
}

private var foregroundStyle: Color {
    switch state {
    case .current:
        Theme.sessionTileCurrentBorder
    case .complete:
        .white
    case .incomplete:
        .white.opacity(0.64)
    case .unavailable:
        .white.opacity(0.4)
    }
}

private var borderColor: Color {
    switch state {
    case .current:
        Theme.sessionTileCurrentBorder
    case .incomplete:
        .white.opacity(0.10)
    case .complete, .unavailable:
        .clear
    }
}

private var borderWidth: CGFloat {
    switch state {
    case .current:
        Theme.sessionTileCurrentBorderWidth
    case .complete, .incomplete, .unavailable:
        1
    }
}
```

In `WorkoutTracker/Views/BlockOverviewView.swift`, add `.disabled(...)` to the tile Button. Change the `Button { ... } label: { ... }` modifier chain so it reads:

```swift
                    .buttonStyle(.plain)
                    .disabled(tile.state == .unavailable)
                    .accessibilityElement(children: .ignore)
```

(Insert the `.disabled(tile.state == .unavailable)` line immediately after `.buttonStyle(.plain)`.)

- [ ] **Step 5: Run the tracker tests to verify they pass**

Run: `swift test --filter "sessionTileStateHasFourCases|tileStateDistinguishesPendingAvailableFromUnavailableSessions|tileStateIsUnavailableEvenWhenItIsTheCurrentSession"`
Expected: PASS (3 tests).

- [ ] **Step 6: Build the app target to confirm no other non-exhaustive switches**

Run: `swift build`
Expected: Build succeeds. (If any other `switch` over `SessionTileState` exists, the compiler flags it here — handle it the same way.)

- [ ] **Step 7: Commit**

```bash
git add WorkoutTracker/Progress/SessionProgressTracker.swift WorkoutTracker/Theme.swift WorkoutTracker/Views/SessionTile.swift WorkoutTracker/Views/BlockOverviewView.swift Tests/Unit/SessionProgressTrackerTests.swift
git commit -m "feat: add unavailable session tile state and rendering"
```

---

## Task 2: Current Session is always an Available Session

No-progress default becomes the first Available Session; a manual override is honored only if it resolves to an Available Session; no Available Session means `nil`.

**Files:**
- Modify: `WorkoutTracker/Progress/SessionProgressTracker.swift`
- Test: `Tests/Unit/SessionProgressTrackerTests.swift`
- Test (fix): `Tests/Unit/WorkoutStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

In `Tests/Unit/SessionProgressTrackerTests.swift`, add a partial-block helper and three tests:

```swift
@MainActor
private func makePartialBlock() -> Block {
    // Week 1: D1 available, D2 unavailable, D3 available, D4 unavailable.
    let parsed = ParsedBlockModel(
        tabName: "Block 28",
        weeks: [
            ParsedWeek(
                number: 1,
                days: (1...4).map { d in
                    let isAvailable = d == 1 || d == 3
                    return ParsedSession(
                        dayNumber: d,
                        date: nil,
                        exercises: isAvailable
                            ? [ParsedExercise(
                                name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil,
                                sets: [ParsedSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: nil)])]
                            : []
                    )
                }
            )
        ]
    )
    return BlockBuilder.makeBlock(from: parsed)
}

@MainActor
@Test func currentSessionDefaultsToFirstAvailableWhenLeadingDayIsUnavailable() {
    let block = makePartialBlock()
    block.weeks[0].sessions[0].exercises = []  // make Day 1 unavailable too

    let current = SessionProgressTracker().currentSession(in: block)

    #expect(current?.week?.number == 1)
    #expect(current?.dayNumber == 3)  // first Available session
}

@MainActor
@Test func currentSessionIsNilWhenNoAvailableSession() {
    let block = makePartialBlock()
    for session in block.weeks[0].sessions { session.exercises = [] }

    #expect(SessionProgressTracker().currentSession(in: block) == nil)
}

@MainActor
@Test func currentSessionIgnoresOverridePointingAtUnavailableSession() {
    let block = makePartialBlock()  // Day 2 (order 2) is unavailable

    let current = SessionProgressTracker().currentSession(in: block, overrideOrder: 2)

    #expect(current?.dayNumber == 1)  // falls back to derived first-available
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "currentSessionDefaultsToFirstAvailableWhenLeadingDayIsUnavailable|currentSessionIsNilWhenNoAvailableSession|currentSessionIgnoresOverridePointingAtUnavailableSession"`
Expected: FAIL — current behavior returns `sessions.first` (Day 1 / Day 2) instead of the first Available / honors the invalid override.

- [ ] **Step 3: Implement the Available-Session guard**

In `WorkoutTracker/Progress/SessionProgressTracker.swift`, add a private helper near `allSessions`:

```swift
private func firstAvailableSession(in block: Block) -> Session? {
    allSessions(block).first { isAvailable($0) }
}
```

Replace `currentSession(in:overrideOrder:)` with:

```swift
func currentSession(in block: Block, overrideOrder: Int? = nil) -> Session? {
    let sessions = allSessions(block)
    let logged = sessions.filter { s in
        s.exercises.contains { $0.sets.contains { $0.state == .logged } }
    }
    guard let derived = logged.last ?? firstAvailableSession(in: block) else { return nil }

    if let overrideOrder,
        let overrideSession = session(at: overrideOrder, in: block),
        isAvailable(overrideSession) {
        return overrideSession
    }

    return derived
}
```

- [ ] **Step 4: Run the tracker tests to verify they pass**

Run: `swift test --filter "currentSessionDefaultsToFirstAvailableWhenLeadingDayIsUnavailable|currentSessionIsNilWhenNoAvailableSession|currentSessionIgnoresOverridePointingAtUnavailableSession|currentSession"`
Expected: PASS. (The broad `currentSession` filter also re-runs the existing override/fallback tests, which still pass — their blocks are fully populated.)

- [ ] **Step 5: Fix the all-empty-block store test**

In `Tests/Unit/WorkoutStoreTests.swift`, the test `loadsBlockAndDefaultsDisplayedToCurrent` builds a Block whose Sessions have `exercises: []`. Under the new rule that Block has no Current Session. Give its Sessions an Exercise. Replace the inner `ParsedSession(dayNumber: d, date: nil, exercises: [])` with:

```swift
                ParsedSession(
                    dayNumber: d,
                    date: nil,
                    exercises: [
                        ParsedExercise(
                            name: "Squat",
                            baseName: "Squat",
                            cadence: nil,
                            coachNote: nil,
                            sets: [ParsedSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: nil)]
                        )
                    ]
                )
```

- [ ] **Step 6: Run the store test to verify it passes**

Run: `swift test --filter loadsBlockAndDefaultsDisplayedToCurrent`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add WorkoutTracker/Progress/SessionProgressTracker.swift Tests/Unit/SessionProgressTrackerTests.swift Tests/Unit/WorkoutStoreTests.swift
git commit -m "feat: keep current session on an available session"
```

---

## Task 3: Move On skips Unavailable Sessions; add `hasSessionAhead`

`nextSession` becomes "next Available Session"; `hasSessionAhead` reports whether any Session (Available or not) lies ahead.

**Files:**
- Modify: `WorkoutTracker/Progress/SessionProgressTracker.swift`
- Test: `Tests/Unit/SessionProgressTrackerTests.swift`

- [ ] **Step 1: Write the failing tests**

In `Tests/Unit/SessionProgressTrackerTests.swift`, add:

```swift
@MainActor
@Test func nextSessionSkipsUnavailableSessions() throws {
    let block = makePartialBlock()  // W1: D1 avail, D2 unavail, D3 avail, D4 unavail
    let tracker = SessionProgressTracker()
    let day1 = block.weeks[0].sessions[0]

    let next = try #require(tracker.nextSession(after: day1, in: block))

    #expect(next.dayNumber == 3)  // skips unavailable Day 2
}

@MainActor
@Test func nextSessionIsNilWhenNoAvailableSessionAhead() {
    let block = makePartialBlock()
    let day3 = block.weeks[0].sessions[2]  // last Available session; Day 4 unavailable ahead

    #expect(SessionProgressTracker().nextSession(after: day3, in: block) == nil)
}

@MainActor
@Test func hasSessionAheadIsTrueWhenUnavailableDaysRemain() {
    let block = makePartialBlock()
    let day3 = block.weeks[0].sessions[2]  // Day 4 (unavailable) lies ahead

    #expect(SessionProgressTracker().hasSessionAhead(after: day3, in: block))
}

@MainActor
@Test func hasSessionAheadIsFalseOnLastStructuralSession() {
    let block = makePartialBlock()
    let day4 = block.weeks[0].sessions[3]  // last day in the block

    #expect(!SessionProgressTracker().hasSessionAhead(after: day4, in: block))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "nextSessionSkipsUnavailableSessions|nextSessionIsNilWhenNoAvailableSessionAhead|hasSessionAheadIsTrueWhenUnavailableDaysRemain|hasSessionAheadIsFalseOnLastStructuralSession"`
Expected: FAIL — `nextSession` currently returns order+1 (Day 2) and `hasSessionAhead` does not exist.

- [ ] **Step 3: Redefine `nextSession` and add `hasSessionAhead`**

In `WorkoutTracker/Progress/SessionProgressTracker.swift`, replace `nextSession(after:in:)` with:

```swift
func nextSession(after session: Session, in block: Block) -> Session? {
    let currentOrder = order(of: session)
    return allSessions(block).first { order(of: $0) > currentOrder && isAvailable($0) }
}

func hasSessionAhead(after session: Session, in block: Block) -> Bool {
    let currentOrder = order(of: session)
    return allSessions(block).contains { order(of: $0) > currentOrder }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "nextSessionSkipsUnavailableSessions|nextSessionIsNilWhenNoAvailableSessionAhead|hasSessionAheadIsTrueWhenUnavailableDaysRemain|hasSessionAheadIsFalseOnLastStructuralSession|nextSessionCrossesWeekBoundaryAndEndsAtLastSession"`
Expected: PASS, including the existing `nextSessionCrossesWeekBoundaryAndEndsAtLastSession` (its Block is fully populated, so "next Available" equals "order+1").

- [ ] **Step 5: Commit**

```bash
git add WorkoutTracker/Progress/SessionProgressTracker.swift Tests/Unit/SessionProgressTrackerTests.swift
git commit -m "feat: advance move on to the next available session"
```

---

## Task 4: Shared partially-uploaded-Block fixture

A single fixture mirroring Block 28 (Day 1 of every week + Week 1 Day 2 Available; rest Unavailable), reused by store, presentation, and UI-screenshot work.

**Files:**
- Modify: `WorkoutTracker/Fixtures/WorkoutFixtureScenarios.swift`
- Modify: `Tests/Support/WorkoutScenarios.swift`
- Test: `Tests/Component/BlockOverviewPresentationTests.swift`

- [ ] **Step 1: Write a failing fixture-shape test**

In `Tests/Component/BlockOverviewPresentationTests.swift`, add:

```swift
@MainActor
@Test func partiallyUploadedScenarioHasFiveAvailableSessions() {
    let scenario = WorkoutScenarios.partiallyUploadedBlock()
    let tracker = SessionProgressTracker()

    let available = scenario.block.weeks
        .flatMap(\.sessions)
        .filter { tracker.isAvailable($0) }
        .map { ($0.week?.number ?? 0, $0.dayNumber) }
        .sorted { $0 < $1 }

    #expect(available == [(1, 1), (1, 2), (2, 1), (3, 1), (4, 1)])
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter partiallyUploadedScenarioHasFiveAvailableSessions`
Expected: FAIL — `WorkoutScenarios.partiallyUploadedBlock()` does not exist.

- [ ] **Step 3: Add the fixture to the app target**

In `WorkoutTracker/Fixtures/WorkoutFixtureScenarios.swift`, add to the `WorkoutFixtureScenarios` enum (next to the other `*Block()` accessors):

```swift
        @MainActor
        static func partiallyUploadedBlock() -> Block {
            WorkoutFixtureBlocks.partiallyUploadedBlock()
        }
```

Add to the `WorkoutFixtureBlocks` enum:

```swift
        @MainActor
        static func partiallyUploadedBlock() -> Block {
            Factory.block(
                weeks: (1...4).map { weekNumber in
                    Factory.week(
                        weekNumber,
                        sessions: (1...4).map { dayNumber in
                            partiallyUploadedSession(weekNumber: weekNumber, dayNumber: dayNumber)
                        }
                    )
                }
            )
        }

        private static func partiallyUploadedSession(weekNumber: Int, dayNumber: Int) -> Session {
            let isAvailable = dayNumber == 1 || (weekNumber == 1 && dayNumber == 2)
            let exercises: [Exercise] = isAvailable
                ? [Factory.accessory(weekNumber: weekNumber, dayNumber: dayNumber)]
                : []
            return Factory.session(weekNumber: weekNumber, dayNumber: dayNumber, exercises: exercises)
        }
```

- [ ] **Step 4: Add the test-support wrapper**

In `Tests/Support/WorkoutScenarios.swift`, add `"partially uploaded block"` to the `names` array, and add this accessor to the `WorkoutScenarios` enum (next to the other scenario accessors):

```swift
    @MainActor
    static func partiallyUploadedBlock() -> BlockScenario {
        scenario(from: WorkoutFixtureScenarios.partiallyUploadedBlock())
    }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter partiallyUploadedScenarioHasFiveAvailableSessions`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add WorkoutTracker/Fixtures/WorkoutFixtureScenarios.swift Tests/Support/WorkoutScenarios.swift Tests/Component/BlockOverviewPresentationTests.swift
git commit -m "test: add partially uploaded block fixture"
```

---

## Task 5: `BlockOverviewPresentation` marks Unavailable Sessions

Verify the presentation propagates `.unavailable` and the "Not uploaded" accessibility value end-to-end. No production code change expected — `BlockOverviewPresentation` already maps `tracker.tileState` and `state.accessibilityValue`.

**Files:**
- Test: `Tests/Component/BlockOverviewPresentationTests.swift`

- [ ] **Step 1: Write the test**

In `Tests/Component/BlockOverviewPresentationTests.swift`, add:

```swift
@MainActor
@Test func blockOverviewPresentationMarksUnpopulatedSessionsUnavailable() {
    let scenario = WorkoutScenarios.partiallyUploadedBlock()

    let presentation = BlockOverviewPresentation(block: scenario.block, currentSession: scenario.currentSession)

    func state(week: Int, day: Int) -> SessionTileState? {
        presentation.tiles.first { $0.weekNumber == week && $0.dayNumber == day }?.state
    }

    #expect(presentation.tiles.count == 16)
    #expect(state(week: 1, day: 1) == .current)       // first Available = Current Session
    #expect(state(week: 1, day: 2) == .incomplete)    // Available, not current
    #expect(state(week: 1, day: 3) == .unavailable)
    #expect(state(week: 1, day: 4) == .unavailable)
    #expect(state(week: 2, day: 1) == .incomplete)
    #expect(state(week: 2, day: 2) == .unavailable)
    #expect(state(week: 4, day: 1) == .incomplete)

    let unavailable = presentation.tiles.first { $0.weekNumber == 1 && $0.dayNumber == 3 }
    #expect(unavailable?.accessibilityValue == "Not uploaded")
}
```

- [ ] **Step 2: Run the test**

Run: `swift test --filter blockOverviewPresentationMarksUnpopulatedSessionsUnavailable`
Expected: PASS immediately (no production change). If it fails, the cause is in `BlockOverviewPresentation` or `tileState` from Task 1 — fix there, do not weaken the test.

- [ ] **Step 3: Commit**

```bash
git add Tests/Component/BlockOverviewPresentationTests.swift
git commit -m "test: cover unavailable tiles in block overview presentation"
```

---

## Task 6: `WorkoutStore` Move On gating + Block-grid request

`canMoveOn` and the celebration guard use `hasSessionAhead`; `advance` routes to the next Available Session or, when none remain ahead, sets `pendingBlockOverviewRequest`.

**Files:**
- Modify: `WorkoutTracker/Stores/WorkoutStore.swift`
- Test: `Tests/Unit/WorkoutStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

In `Tests/Unit/WorkoutStoreTests.swift`, add a partial-block store helper (place it near `makeStore`):

```swift
@MainActor
private func makePartialStore(defaults: UserDefaults? = nil) throws -> WorkoutStoreFixture {
    let container = try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        configurations: ModelConfiguration(
            "partial-store-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
    let ctx = container.mainContext
    ctx.insert(WorkoutFixtureScenarios.partiallyUploadedBlock())
    try ctx.save()
    let store = try WorkoutStore(context: ctx, defaults: defaults ?? makeDefaults())
    store.reload()
    return WorkoutStoreFixture(store: store, container: container)
}
```

Add three tests:

```swift
@MainActor
@Test func moveOnSkipsUnavailableDaysToNextAvailableSession() throws {
    let fixture = try makePartialStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    store.moveOn()  // W1D1 -> W1D2 (Available)
    #expect(store.currentSession?.week?.number == 1)
    #expect(store.currentSession?.dayNumber == 2)

    store.moveOn()  // skips W1D3/W1D4 -> W2D1
    #expect(store.currentSession?.week?.number == 2)
    #expect(store.currentSession?.dayNumber == 1)
}

@MainActor
@Test func canMoveOnIsTrueOnLastAvailableSessionWhenUnavailableDaysRemain() throws {
    let fixture = try makePartialStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    store.moveOn(); store.moveOn(); store.moveOn(); store.moveOn()  // -> W4D1

    #expect(store.currentSession?.week?.number == 4)
    #expect(store.currentSession?.dayNumber == 1)
    #expect(store.canMoveOn)  // W4D2-D4 (Unavailable) lie ahead
}

@MainActor
@Test func moveOnFromLastAvailableSessionRequestsBlockOverview() throws {
    let fixture = try makePartialStore()
    defer { withExtendedLifetime(fixture.container) {} }
    let store = fixture.store

    store.moveOn(); store.moveOn(); store.moveOn(); store.moveOn()  // -> W4D1
    #expect(store.pendingBlockOverviewRequest == false)

    store.moveOn()  // no Available session ahead -> request the grid, do not advance

    #expect(store.pendingBlockOverviewRequest)
    #expect(store.currentSession?.week?.number == 4)
    #expect(store.currentSession?.dayNumber == 1)

    store.clearBlockOverviewRequest()
    #expect(store.pendingBlockOverviewRequest == false)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "moveOnSkipsUnavailableDaysToNextAvailableSession|canMoveOnIsTrueOnLastAvailableSessionWhenUnavailableDaysRemain|moveOnFromLastAvailableSessionRequestsBlockOverview"`
Expected: FAIL — `pendingBlockOverviewRequest`/`clearBlockOverviewRequest()` do not exist; `canMoveOn` is false on W4D1; `moveOn` does not skip Unavailable days correctly.

- [ ] **Step 3: Implement the store changes**

In `WorkoutTracker/Stores/WorkoutStore.swift`:

Add the observable flag next to `moveOnCelebrationSession`:

```swift
    private(set) var pendingBlockOverviewRequest = false
```

Replace `canMoveOn`:

```swift
    var canMoveOn: Bool {
        guard let block, let currentSession else { return false }
        return tracker.hasSessionAhead(after: currentSession, in: block)
    }
```

Replace `requestMoveOnCelebration()`:

```swift
    func requestMoveOnCelebration() {
        guard
            let block,
            let currentSession,
            tracker.hasSessionAhead(after: currentSession, in: block)
        else { return }

        moveOnCelebrationSession = currentSession
        displayedSession = currentSession
        shouldPreserveDisplayedSessionOnReload = false
    }
```

Replace `advance(after:)`:

```swift
    private func advance(after session: Session) {
        guard let block else { return }

        if let nextSession = tracker.nextSession(after: session, in: block) {
            defaults.set(tracker.order(of: nextSession), forKey: currentSessionOverrideKey(for: block.tabName))
            currentSessionOverrideRevision += 1
            displayedSession = nextSession
            shouldPreserveDisplayedSessionOnReload = false
        } else if tracker.hasSessionAhead(after: session, in: block) {
            pendingBlockOverviewRequest = true
        }
    }
```

Add the clear method (next to `showCurrent()`):

```swift
    func clearBlockOverviewRequest() {
        pendingBlockOverviewRequest = false
    }
```

- [ ] **Step 4: Run the new tests to verify they pass**

Run: `swift test --filter "moveOnSkipsUnavailableDaysToNextAvailableSession|canMoveOnIsTrueOnLastAvailableSessionWhenUnavailableDaysRemain|moveOnFromLastAvailableSessionRequestsBlockOverview"`
Expected: PASS.

- [ ] **Step 5: Run the full store + tracker suites for regressions**

Run: `swift test --filter "WorkoutStore|SessionProgressTracker"`
Expected: PASS. In particular `canMoveOnIsFalseOnLastSession`, `moveOnAdvancesCurrentSessionAndDisplayedSession`, `dismissingMoveOnCelebrationAdvancesFromCapturedSession`, and `moveOnCrossesWeekBoundaryAndDropsPriorWeekOpenExercises` still pass (their Blocks are fully populated).

- [ ] **Step 6: Commit**

```bash
git add WorkoutTracker/Stores/WorkoutStore.swift Tests/Unit/WorkoutStoreTests.swift
git commit -m "feat: move on to grid when no available session remains"
```

---

## Task 7: `SessionView` navigates to the grid after the terminal Move On

Consume `pendingBlockOverviewRequest` and push `BlockOverviewView` programmatically.

**Files:**
- Modify: `WorkoutTracker/Views/SessionView.swift`

- [ ] **Step 1: Add the navigation state**

In `WorkoutTracker/Views/SessionView.swift`, add a state property alongside the other `@State` declarations (after `@State private var isSessionControlsSyncInFlight = false`):

```swift
    @State private var showsBlockOverview = false
```

- [ ] **Step 2: Wire the destination and the request consumer**

Attach two modifiers to the outer `Group` in `body`. Place them immediately after the existing `.sheet(isPresented: $isSettingsPresented) { SettingsView() }` modifier:

```swift
        .navigationDestination(isPresented: $showsBlockOverview) {
            if let block = workout.block {
                BlockOverviewView(block: block, currentSession: workout.currentSession)
            }
        }
        .onChange(of: workout.pendingBlockOverviewRequest) { _, requested in
            if requested {
                showsBlockOverview = true
                workout.clearBlockOverviewRequest()
            }
        }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 4: Run the full test suite**

Run: `swift test`
Expected: PASS (no regressions).

- [ ] **Step 5: Commit**

```bash
git add WorkoutTracker/Views/SessionView.swift
git commit -m "feat: open block grid after final move on celebration"
```

---

## Task 8: UI fixture launch arg + screenshot review

Seed the partially-uploaded Block for unattended UI verification and review the Unavailable tile's appearance.

**Files:**
- Modify: `WorkoutTracker/Fixtures/UITestFixture.swift`

- [ ] **Step 1: Add the launch arg and seed branch**

In `WorkoutTracker/Fixtures/UITestFixture.swift`, add the flag next to the other `startsWith*` flags:

```swift
        static var startsWithPartiallyUploadedBlock: Bool {
            ProcessInfo.processInfo.arguments.contains("-UITEST_PARTIAL_BLOCK")
        }
```

Replace the `block` assignment in `seed(into:)` with:

```swift
            let block: Block
            if startsWithOpenExercises {
                block = WorkoutFixtureScenarios.openExercisesBlock()
            } else if startsWithPartiallyUploadedBlock {
                block = WorkoutFixtureScenarios.partiallyUploadedBlock()
            } else {
                block = WorkoutFixtureScenarios.uiLaunchBlock()
            }
```

- [ ] **Step 2: Build for the simulator**

Use XcodeBuildMCP. First confirm session defaults:
Run: `session_show_defaults`
Then build & run with the fixture args. Launch arguments must include `-UITEST_FIXTURE -UITEST_PARTIAL_BLOCK`.
Expected: App boots straight into `SessionView` on Week 1 · Day 1.

- [ ] **Step 3: Capture the Block grid screenshot**

Tap the `Week 1 · Day 1` location label (accessibility identifier `session-location-button`) to push the Block grid, then screenshot.
Run (XcodeBuildMCP): `tap` the `session-location-button`, then `screenshot`.
Expected: A 4×4 grid where W1D1 is Current, W1D2/W2D1/W3D1/W4D1 are live tiles, and the remaining 11 tiles are recessed "Not uploaded" tiles.

- [ ] **Step 4: Review the Unavailable tile appearance**

Run the `ui-screenshot-reviewer` agent against the captured screenshot. Confirm: the Unavailable tiles read as intentional and polished (recessed/frosted, clear "Not uploaded" label), distinct from both Complete and Incomplete tiles, and consistent with the Liquid Glass system. Address any feedback by adjusting `Theme.sessionTileUnavailable`/`sessionTileUnavailableOpacity` or the `SessionTile` layout from Task 1, then re-capture.

- [ ] **Step 5: Verify inert tap**

Tap one of the "Not uploaded" tiles.
Expected: Nothing happens — no navigation, no visible change.

- [ ] **Step 6: Commit**

```bash
git add WorkoutTracker/Fixtures/UITestFixture.swift
git commit -m "test: add partially uploaded block ui fixture"
```

---

## Task 9: Final verification

- [ ] **Step 1: Full test suite**

Run: `swift test`
Expected: All tests pass.

- [ ] **Step 2: Lint/format**

Run: `swift-format -i -r WorkoutTracker/ Tests/`
Then build to confirm SwiftLint (build-tool plugin) is clean: `swift build`
Expected: No formatting diffs that break the build; no lint errors.

- [ ] **Step 3: Confirm acceptance criteria**

Re-read `docs/superpowers/specs/2026-05-30-partially-uploaded-block-design.md` "Acceptance Criteria" and confirm each item is satisfied by the tests/UI verification above.

---

## Self-Review

**Spec coverage:**
- Per-Session availability → Task 1 (`isAvailable`, `tileState`).
- Distinct, polished, inert Unavailable tile → Task 1 (rendering + `.disabled`), Task 8 (screenshot review).
- "Not uploaded" label + accessibility → Task 1, Task 5.
- Current Session always Available; first-Available default; `nil` when none → Task 2.
- Override never resolves to Unavailable → Task 2.
- Move On skips Unavailable to next Available → Task 3, Task 6.
- Move On offered while any session ahead; celebration on terminal day; grid afterward → Task 6 (store), Task 7 (navigation).
- Full Block unchanged → covered by existing tests re-run in Task 6 Step 5.
- Whole-Block-empty → existing empty state, via Task 2 (`currentSession == nil`).
- Makeups exclude Unavailable days → no code change; Unavailable Sessions have no Exercises (existing `openExercises` filter); existing tracker open-exercise tests still pass.
- Full 16-cell skeleton always present → no placeholder-synthesis code (out of scope, per spec).

**Placeholder scan:** No TBD/TODO; every code step shows complete code; every command lists expected output. UI styling values are concrete (`Theme.sessionTileUnavailable*`) with a screenshot-review loop to tune them.

**Type consistency:** `SessionTileState.unavailable`, `isAvailable(_:)`, `firstAvailableSession(in:)`, `nextSession(after:in:)`, `hasSessionAhead(after:in:)`, `pendingBlockOverviewRequest`, `clearBlockOverviewRequest()`, `WorkoutScenarios.partiallyUploadedBlock()`, `WorkoutFixtureScenarios.partiallyUploadedBlock()`, and `-UITEST_PARTIAL_BLOCK` are named identically wherever referenced across tasks.
