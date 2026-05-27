# Session Progression + Block Overview Implementation Plan (Plan 4 of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Move On to advance sessions, surface Open Exercises for makeup work, and provide a 4×4 Block Overview grid for at-a-glance progress.

**Architecture:** Extends `SessionProgressTracker` with tile state derivation and open-exercise queries. `WorkoutStore` gains Move On logic with `UserDefaults` persistence (injected for test isolation). Two new views (`BlockOverviewView`, `SessionTile`) provide the grid; `SessionView` gains breadcrumb navigation, an open exercises section, and a Move On button.

**Tech Stack:** Swift 6, iOS 26, SwiftUI, SwiftData, Swift Testing, UserDefaults.

**Reference docs:** spec `docs/superpowers/specs/2026-05-24-high-level-app-design.md`; glossary `CONTEXT.md`; ADRs `docs/adr/0001..0004`; PRD issue #1; redesign PRD issue #13.

---

## Current Repo State To Preserve

- Plans 1–3 are implemented (or in progress via issues #22–#24). Do not repeat prior work.
- Current visual language: Liquid Glass cards, mint/emerald active-set system. Follow existing `Theme` patterns.
- `ActiveSetFocusManager`, `ExerciseSection`, `SmartValuePills`, `ActiveSetCard` — all wired and working. Do not modify.
- Test runner: `swift test` for package-level tests; `xcodebuild -project WorkoutTracker.xcodeproj -scheme WorkoutTracker -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` for app target.
- `Package.swift` excludes `Views/`, `GoogleAuth.swift`, `GoogleSheetsClient.swift`, `WorkoutTrackerApp.swift`. View-only changes can't be tested with `swift test`.

## Design Decisions

**Move On persistence:** The manual advance is stored as a session order integer in `UserDefaults`, keyed by block tab name (`advancedToOrder_{tabName}`). Scoped to the current block — irrelevant when a new block syncs. `UserDefaults` instance is injected into `WorkoutStore` for test isolation.

**Open Exercises navigation:** Open exercises from past sessions in the current week are displayed inline as compact tappable cards. Tapping navigates to the source session (`WorkoutStore.show(week:day:)`), where the athlete logs sets normally. Writes target the original session's column via the existing `PendingWrite` path (the exercise's `.session` backlink carries the correct week/day). A "Back to Current" banner returns to the live edge.

**Block Overview navigation:** `SessionView`'s breadcrumb becomes a `NavigationLink` pushing `BlockOverviewView`. Tapping a session tile sets `displayedSession` and pops back to root. The navigation stack is never deeper than Session → Overview.

**Week boundaries:** Handled by derivation. Open exercises come only from sessions **before** `currentSession` in the current week. When `currentSession` advances to Week N+1 (by logging or Move On), `currentWeek` changes, and Week N's open exercises stop appearing.

## File Structure

```
WorkoutTracker/
  Progress/
    SessionProgressTracker.swift       # modify: SessionTileState, tileState, openExercises, order, nextSession
  Stores/
    WorkoutStore.swift                 # modify: defaults injection, moveOn(), showCurrent(), openExercises, canMoveOn
  Theme.swift                          # modify: tile colors
  Views/
    BlockOverviewView.swift            # new: 4×4 grid
    SessionTile.swift                  # new: individual tile
    SessionView.swift                  # modify: breadcrumb nav, open exercises, move on, back-to-current
WorkoutTrackerTests/
  SessionProgressTrackerTests.swift    # modify: tile state, open exercises, week boundary, move-on-override tests
  WorkoutStoreTests.swift              # modify: moveOn tests (with injected UserDefaults)
```

---

## Task 1: SessionTileState + Tile State Derivation

**Files:**
- Modify: `WorkoutTracker/Progress/SessionProgressTracker.swift`
- Modify: `WorkoutTrackerTests/SessionProgressTrackerTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `WorkoutTrackerTests/SessionProgressTrackerTests.swift`:

```swift
@MainActor
private func makeMultiSetBlock() -> Block {
    let parsed = ParsedBlockModel(
        tabName: "Block 27",
        weeks: (1...2).map { w in
            ParsedWeek(
                number: w,
                days: (1...4).map { d in
                    ParsedSession(
                        dayNumber: d,
                        date: nil,
                        exercises: [
                            ParsedExercise(
                                name: "Squat",
                                baseName: "Squat",
                                cadence: nil,
                                coachNote: nil,
                                sets: [
                                    ParsedSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: nil),
                                    ParsedSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: nil)
                                ]
                            ),
                            ParsedExercise(
                                name: "Bench",
                                baseName: "Bench",
                                cadence: nil,
                                coachNote: nil,
                                sets: [
                                    ParsedSet(index: 0, prescribedReps: "8", prescribedLoad: "RPE7", percentOneRM: nil)
                                ]
                            )
                        ]
                    )
                }
            )
        }
    )
    return BlockBuilder.makeBlock(from: parsed)
}

// MARK: - Tile State

@MainActor
@Test func tileStateCurrentForActiveSession() {
    let block = makeMultiSetBlock()
    block.weeks[0].sessions[0].exercises.sorted { $0.order < $1.order }[0]
        .sets.sorted { $0.index < $1.index }[0].state = .logged
    let tracker = SessionProgressTracker()
    let current = tracker.currentSession(in: block)
    #expect(tracker.tileState(for: block.weeks[0].sessions[0], currentSession: current) == .current)
}

@MainActor
@Test func tileStateCompleteForFullyLoggedPastSession() {
    let block = makeMultiSetBlock()
    let w1d1 = block.weeks[0].sessions[0]
    for ex in w1d1.exercises { for s in ex.sets { s.state = .logged } }
    block.weeks[0].sessions[1].exercises[0].sets[0].state = .logged
    let tracker = SessionProgressTracker()
    let current = tracker.currentSession(in: block)
    #expect(current?.dayNumber == 2)
    #expect(tracker.tileState(for: w1d1, currentSession: current) == .complete)
}

@MainActor
@Test func tileStateUpcomingForUntouchedFutureSession() {
    let block = makeMultiSetBlock()
    block.weeks[0].sessions[0].exercises[0].sets[0].state = .logged
    let tracker = SessionProgressTracker()
    let current = tracker.currentSession(in: block)
    #expect(tracker.tileState(for: block.weeks[0].sessions[2], currentSession: current) == .upcoming)
}

@MainActor
@Test func tileStateHasOpenExercisesForPartiallyLoggedPastSession() {
    let block = makeMultiSetBlock()
    let w1d1 = block.weeks[0].sessions[0]
    w1d1.exercises.sorted { $0.order < $1.order }[0]
        .sets.sorted { $0.index < $1.index }[0].state = .logged
    block.weeks[0].sessions[1].exercises[0].sets[0].state = .logged
    let tracker = SessionProgressTracker()
    let current = tracker.currentSession(in: block)
    #expect(current?.dayNumber == 2)
    #expect(tracker.tileState(for: w1d1, currentSession: current) == .hasOpenExercises)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SessionProgressTracker 2>&1 | tail -20`
Expected: FAIL — `SessionTileState` and `tileState` are not defined.

- [ ] **Step 3: Add SessionTileState enum and tileState method**

Add to `WorkoutTracker/Progress/SessionProgressTracker.swift`:

```swift
enum SessionTileState: Equatable, Sendable {
    case complete
    case hasOpenExercises
    case current
    case upcoming
}
```

Add this method to `SessionProgressTracker`:

```swift
func tileState(for session: Session, currentSession: Session?) -> SessionTileState {
    if order(session) == currentSession.map({ order($0) }) {
        return .current
    }
    let allSets = session.exercises.flatMap(\.sets)
    guard !allSets.isEmpty else { return .upcoming }
    if allSets.allSatisfy({ $0.state == .logged || $0.state == .skipped }) {
        return .complete
    }
    if allSets.contains(where: { $0.state == .logged || $0.state == .skipped }) {
        return .hasOpenExercises
    }
    return .upcoming
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SessionProgressTracker 2>&1 | tail -20`
Expected: All 6 tests PASS (4 new + 2 existing).

- [ ] **Step 5: Commit**

```bash
git add WorkoutTracker/Progress/SessionProgressTracker.swift WorkoutTrackerTests/SessionProgressTrackerTests.swift
git commit -m "$(cat <<'EOF'
feat: add SessionTileState derivation to SessionProgressTracker

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Open Exercises Query

**Files:**
- Modify: `WorkoutTracker/Progress/SessionProgressTracker.swift`
- Modify: `WorkoutTrackerTests/SessionProgressTrackerTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `WorkoutTrackerTests/SessionProgressTrackerTests.swift`:

```swift
// MARK: - Open Exercises

@MainActor
@Test func openExercisesReturnsPendingFromPastSessionsInCurrentWeek() {
    let block = makeMultiSetBlock()
    let w1d1 = block.weeks[0].sessions[0]
    w1d1.exercises.sorted { $0.order < $1.order }[0]
        .sets.sorted { $0.index < $1.index }[0].state = .logged
    block.weeks[0].sessions[1].exercises[0].sets[0].state = .logged
    let tracker = SessionProgressTracker()
    let current = tracker.currentSession(in: block)
    #expect(current?.dayNumber == 2)
    let open = tracker.openExercises(in: block, currentSession: current)
    #expect(open.count == 2)
    #expect(open[0].name == "Squat")
    #expect(open[1].name == "Bench")
}

@MainActor
@Test func openExercisesExcludesFullyLoggedPastSessions() {
    let block = makeMultiSetBlock()
    let w1d1 = block.weeks[0].sessions[0]
    for ex in w1d1.exercises { for s in ex.sets { s.state = .logged } }
    block.weeks[0].sessions[1].exercises[0].sets[0].state = .logged
    let tracker = SessionProgressTracker()
    let current = tracker.currentSession(in: block)
    let open = tracker.openExercises(in: block, currentSession: current)
    #expect(open.isEmpty)
}

@MainActor
@Test func openExercisesEmptyWhenOnFirstSession() {
    let block = makeMultiSetBlock()
    let tracker = SessionProgressTracker()
    let current = tracker.currentSession(in: block)
    #expect(current?.dayNumber == 1)
    let open = tracker.openExercises(in: block, currentSession: current)
    #expect(open.isEmpty)
}

@MainActor
@Test func openExercisesAbandonedOnWeekAdvance() {
    let block = makeMultiSetBlock()
    block.weeks[0].sessions[0].exercises[0].sets[0].state = .logged
    block.weeks[1].sessions[0].exercises[0].sets[0].state = .logged
    let tracker = SessionProgressTracker()
    let current = tracker.currentSession(in: block)
    #expect(current?.week?.number == 2)
    let open = tracker.openExercises(in: block, currentSession: current)
    #expect(open.isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SessionProgressTracker 2>&1 | tail -20`
Expected: FAIL — `openExercises` is not defined.

- [ ] **Step 3: Implement openExercises**

Add to `SessionProgressTracker`:

```swift
func openExercises(in block: Block, currentSession: Session?) -> [Exercise] {
    guard let week = currentSession?.week else { return [] }
    let currentOrder = currentSession.map { order($0) } ?? 0
    return week.sessions
        .filter { order($0) < currentOrder }
        .sorted { $0.dayNumber < $1.dayNumber }
        .flatMap { session in
            session.exercises
                .sorted { $0.order < $1.order }
                .filter { $0.sets.contains { $0.state == .pending } }
        }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SessionProgressTracker 2>&1 | tail -20`
Expected: All 10 tests PASS (4 new + 6 from Task 1).

- [ ] **Step 5: Commit**

```bash
git add WorkoutTracker/Progress/SessionProgressTracker.swift WorkoutTrackerTests/SessionProgressTrackerTests.swift
git commit -m "$(cat <<'EOF'
feat: add open exercises query to SessionProgressTracker

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Move On + Session Navigation Helpers

**Files:**
- Modify: `WorkoutTracker/Progress/SessionProgressTracker.swift`
- Modify: `WorkoutTracker/Stores/WorkoutStore.swift`
- Modify: `WorkoutTrackerTests/SessionProgressTrackerTests.swift`
- Modify: `WorkoutTrackerTests/WorkoutStoreTests.swift`

- [ ] **Step 1: Write the failing tracker tests**

Append to `WorkoutTrackerTests/SessionProgressTrackerTests.swift`:

```swift
// MARK: - Session Navigation

@MainActor
@Test func nextSessionAdvancesWithinWeek() {
    let block = makeBlock()
    let tracker = SessionProgressTracker()
    let w1d1 = block.weeks[0].sessions[0]
    let next = tracker.nextSession(after: w1d1, in: block)
    #expect(next?.dayNumber == 2)
    #expect(next?.week?.number == 1)
}

@MainActor
@Test func nextSessionCrossesWeekBoundary() {
    let block = makeBlock()
    let tracker = SessionProgressTracker()
    let w1d4 = block.weeks[0].sessions[3]
    let next = tracker.nextSession(after: w1d4, in: block)
    #expect(next?.dayNumber == 1)
    #expect(next?.week?.number == 2)
}

@MainActor
@Test func nextSessionReturnsNilAtEnd() {
    let block = makeBlock()
    let tracker = SessionProgressTracker()
    let w2d4 = block.weeks[1].sessions[3]
    #expect(tracker.nextSession(after: w2d4, in: block) == nil)
}

@MainActor
@Test func currentSessionRespectsAdvanceOverride() {
    let block = makeBlock()
    let tracker = SessionProgressTracker()
    let w1d1 = block.weeks[0].sessions[0]
    w1d1.exercises[0].sets[0].state = .logged
    let derived = tracker.currentSession(in: block)
    #expect(derived?.dayNumber == 1)
    let overridden = tracker.currentSession(in: block, advancedToOrder: 3)
    #expect(overridden?.dayNumber == 3)
    #expect(overridden?.week?.number == 1)
}

@MainActor
@Test func advanceOverrideIgnoredWhenDerivedIsPastIt() {
    let block = makeBlock()
    let tracker = SessionProgressTracker()
    block.weeks[0].sessions[2].exercises[0].sets[0].state = .logged
    let result = tracker.currentSession(in: block, advancedToOrder: 2)
    #expect(result?.dayNumber == 3)
}

@MainActor
@Test func orderAndSessionAtRoundTrip() {
    let block = makeBlock()
    let tracker = SessionProgressTracker()
    let w1d3 = block.weeks[0].sessions[2]
    let o = tracker.order(of: w1d3)
    #expect(o == 3)
    let found = tracker.session(at: o, in: block)
    #expect(found?.dayNumber == 3)
    #expect(found?.week?.number == 1)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SessionProgressTracker 2>&1 | tail -20`
Expected: FAIL — `nextSession`, `order(of:)`, `session(at:)`, and the `advancedToOrder` parameter are not defined.

- [ ] **Step 3: Implement tracker additions**

Replace the contents of `WorkoutTracker/Progress/SessionProgressTracker.swift` with:

```swift
import Foundation

enum SessionTileState: Equatable, Sendable {
    case complete
    case hasOpenExercises
    case current
    case upcoming
}

struct SessionProgressTracker {
    private func order(_ s: Session) -> Int { ((s.week?.number ?? 1) - 1) * 4 + s.dayNumber }

    private func allSessions(_ block: Block) -> [Session] {
        block.weeks.flatMap { $0.sessions }.sorted { order($0) < order($1) }
    }

    func currentSession(in block: Block, advancedToOrder: Int? = nil) -> Session? {
        let sessions = allSessions(block)
        let logged = sessions.filter { s in
            s.exercises.contains { $0.sets.contains { $0.state == .logged } }
        }
        let derived = logged.last ?? sessions.first
        if let target = advancedToOrder,
           let derivedOrder = derived.map({ order($0) }),
           target > derivedOrder,
           let advanced = sessions.first(where: { order($0) == target }) {
            return advanced
        }
        return derived
    }

    func currentWeek(in block: Block) -> Week? {
        currentSession(in: block)?.week
    }

    func tileState(for session: Session, currentSession: Session?) -> SessionTileState {
        if order(session) == currentSession.map({ order($0) }) {
            return .current
        }
        let allSets = session.exercises.flatMap(\.sets)
        guard !allSets.isEmpty else { return .upcoming }
        if allSets.allSatisfy({ $0.state == .logged || $0.state == .skipped }) {
            return .complete
        }
        if allSets.contains(where: { $0.state == .logged || $0.state == .skipped }) {
            return .hasOpenExercises
        }
        return .upcoming
    }

    func openExercises(in block: Block, currentSession: Session?) -> [Exercise] {
        guard let week = currentSession?.week else { return [] }
        let currentOrder = currentSession.map { order($0) } ?? 0
        return week.sessions
            .filter { order($0) < currentOrder }
            .sorted { $0.dayNumber < $1.dayNumber }
            .flatMap { session in
                session.exercises
                    .sorted { $0.order < $1.order }
                    .filter { $0.sets.contains { $0.state == .pending } }
            }
    }

    func order(of session: Session) -> Int { order(session) }

    func session(at targetOrder: Int, in block: Block) -> Session? {
        allSessions(block).first { order($0) == targetOrder }
    }

    func nextSession(after session: Session, in block: Block) -> Session? {
        let all = allSessions(block)
        let sessionOrder = order(session)
        return all.first { order($0) > sessionOrder }
    }
}
```

- [ ] **Step 4: Run tracker tests**

Run: `swift test --filter SessionProgressTracker 2>&1 | tail -20`
Expected: All 16 tests PASS.

- [ ] **Step 5: Write the failing WorkoutStore tests**

Replace the contents of `WorkoutTrackerTests/WorkoutStoreTests.swift` with:

```swift
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
private func makeStoreWithBlock(
    weekCount: Int = 1,
    exercisesPerSession: [ParsedExercise] = []
) throws -> (WorkoutStore, ModelContext, UserDefaults) {
    let container = try ModelContainer(
        for: Block.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let ctx = container.mainContext
    let parsed = ParsedBlockModel(
        tabName: "Block 27",
        weeks: (1...weekCount).map { w in
            ParsedWeek(
                number: w,
                days: (1...4).map { d in
                    ParsedSession(dayNumber: d, date: nil, exercises: exercisesPerSession)
                }
            )
        }
    )
    ctx.insert(BlockBuilder.makeBlock(from: parsed))
    try ctx.save()
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = WorkoutStore(context: ctx, defaults: defaults)
    return (store, ctx, defaults)
}

@MainActor
@Test func loadsBlockAndDefaultsDisplayedToCurrent() throws {
    let (store, _, _) = try makeStoreWithBlock()
    store.reload()
    #expect(store.block?.tabName == "Block 27")
    #expect(store.displayedSession?.dayNumber == 1)
    store.show(week: 1, day: 3)
    #expect(store.displayedSession?.dayNumber == 3)
}

@MainActor
@Test func moveOnAdvancesToNextSession() throws {
    let exercises = [
        ParsedExercise(
            name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil,
            sets: [ParsedSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: nil)]
        )
    ]
    let (store, _, _) = try makeStoreWithBlock(weekCount: 2, exercisesPerSession: exercises)
    store.reload()
    store.block!.weeks.first { $0.number == 1 }!
        .sessions.first { $0.dayNumber == 1 }!
        .exercises[0].sets[0].state = .logged
    store.reload()
    #expect(store.currentSession?.dayNumber == 1)
    store.moveOn()
    #expect(store.currentSession?.dayNumber == 2)
    #expect(store.displayedSession?.dayNumber == 2)
}

@MainActor
@Test func moveOnPersistsAcrossReload() throws {
    let exercises = [
        ParsedExercise(
            name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil,
            sets: [ParsedSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: nil)]
        )
    ]
    let (store, _, _) = try makeStoreWithBlock(weekCount: 2, exercisesPerSession: exercises)
    store.reload()
    store.block!.weeks.first { $0.number == 1 }!
        .sessions.first { $0.dayNumber == 1 }!
        .exercises[0].sets[0].state = .logged
    store.reload()
    store.moveOn()
    #expect(store.currentSession?.dayNumber == 2)
    store.reload()
    #expect(store.currentSession?.dayNumber == 2)
}

@MainActor
@Test func moveOnOverrideIgnoredWhenLoggingCatchesUp() throws {
    let exercises = [
        ParsedExercise(
            name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil,
            sets: [ParsedSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: nil)]
        )
    ]
    let (store, _, _) = try makeStoreWithBlock(weekCount: 2, exercisesPerSession: exercises)
    store.reload()
    store.block!.weeks.first { $0.number == 1 }!
        .sessions.first { $0.dayNumber == 1 }!
        .exercises[0].sets[0].state = .logged
    store.reload()
    store.moveOn()
    #expect(store.currentSession?.dayNumber == 2)
    store.block!.weeks.first { $0.number == 1 }!
        .sessions.first { $0.dayNumber == 3 }!
        .exercises[0].sets[0].state = .logged
    store.reload()
    #expect(store.currentSession?.dayNumber == 3)
}

@MainActor
@Test func showCurrentResetsDisplayedSession() throws {
    let (store, _, _) = try makeStoreWithBlock()
    store.reload()
    store.show(week: 1, day: 3)
    #expect(store.displayedSession?.dayNumber == 3)
    store.showCurrent()
    #expect(store.displayedSession?.dayNumber == 1)
}

@MainActor
@Test func canMoveOnFalseOnLastSession() throws {
    let exercises = [
        ParsedExercise(
            name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil,
            sets: [ParsedSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: nil)]
        )
    ]
    let (store, _, _) = try makeStoreWithBlock(weekCount: 1, exercisesPerSession: exercises)
    store.reload()
    store.block!.weeks.first { $0.number == 1 }!
        .sessions.first { $0.dayNumber == 4 }!
        .exercises[0].sets[0].state = .logged
    store.reload()
    #expect(store.currentSession?.dayNumber == 4)
    #expect(!store.canMoveOn)
}
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `swift test --filter WorkoutStore 2>&1 | tail -20`
Expected: FAIL — `moveOn()`, `showCurrent()`, `canMoveOn`, and the `defaults` parameter are not defined.

- [ ] **Step 7: Implement WorkoutStore changes**

Replace the contents of `WorkoutTracker/Stores/WorkoutStore.swift` with:

```swift
import Foundation
import SwiftData

enum WorkoutLoggingError: Error, Equatable {
    case missingExercise
    case missingSession
    case missingWeek
    case missingBlock
}

@MainActor
@Observable
final class WorkoutStore {
    private(set) var block: Block?
    private(set) var displayedSession: Session?

    private let context: ModelContext
    private let tracker = SessionProgressTracker()
    private let defaults: UserDefaults

    init(context: ModelContext, defaults: UserDefaults = .standard) {
        self.context = context
        self.defaults = defaults
    }

    var currentSession: Session? {
        guard let block else { return nil }
        let stored = defaults.integer(forKey: advanceKey(for: block))
        return tracker.currentSession(in: block, advancedToOrder: stored > 0 ? stored : nil)
    }

    var isViewingLiveEdge: Bool { displayedSession?.persistentModelID == currentSession?.persistentModelID }

    var openExercises: [Exercise] {
        guard let block else { return [] }
        return tracker.openExercises(in: block, currentSession: currentSession)
    }

    var canMoveOn: Bool {
        guard let block, let current = currentSession else { return false }
        return tracker.nextSession(after: current, in: block) != nil
    }

    func reload() {
        block = try? context.fetch(FetchDescriptor<Block>()).first
        displayedSession = currentSession
    }

    func show(week: Int, day: Int) {
        displayedSession = block?.weeks.first { $0.number == week }?.sessions.first { $0.dayNumber == day }
    }

    func showCurrent() {
        displayedSession = currentSession
    }

    func moveOn() {
        guard let block, let current = currentSession else { return }
        guard let next = tracker.nextSession(after: current, in: block) else { return }
        defaults.set(tracker.order(of: next), forKey: advanceKey(for: block))
        displayedSession = next
    }

    // MARK: - Optimistic Logging

    func log(_ set: ExerciseSet, as log: SetLog) throws {
        let previousValue = set.setLog?.formatted ?? ""
        let previousRPE = set.setLog.map { rpeLabel($0.rpe) } ?? ""
        set.setLog = log
        set.state = .logged
        try enqueue(
            for: set,
            column: .notes,
            operation: .upsert,
            valueToWrite: log.formatted,
            expectedCurrentValue: previousValue
        )
        if isFinalSet(set) {
            try enqueue(
                for: set,
                column: .lastSetRPE,
                operation: .upsert,
                valueToWrite: rpeLabel(log.rpe),
                expectedCurrentValue: previousRPE
            )
        }
        try updateLastPerformed(for: set, log: log)
        try context.save()
    }

    func skip(_ set: ExerciseSet) throws {
        let previousValue = set.setLog?.formatted ?? (set.state == .skipped ? "skip" : "")
        set.setLog = nil
        set.state = .skipped
        try enqueue(
            for: set,
            column: .notes,
            operation: .upsert,
            valueToWrite: "skip",
            expectedCurrentValue: previousValue
        )
        try context.save()
    }

    func deleteLog(for set: ExerciseSet) throws {
        let previousValue = set.setLog?.formatted ?? (set.state == .skipped ? "skip" : "")
        let previousRPE = set.setLog.map { rpeLabel($0.rpe) } ?? ""
        set.setLog = nil
        set.state = .pending
        try enqueue(
            for: set,
            column: .notes,
            operation: .delete,
            valueToWrite: nil,
            expectedCurrentValue: previousValue
        )
        if isFinalSet(set), !previousRPE.isEmpty {
            try enqueue(
                for: set,
                column: .lastSetRPE,
                operation: .delete,
                valueToWrite: nil,
                expectedCurrentValue: previousRPE
            )
        }
        try context.save()
    }

    // MARK: - Private Helpers

    private func advanceKey(for block: Block) -> String {
        "advancedToOrder_\(block.tabName)"
    }

    private func enqueue(
        for set: ExerciseSet,
        column: PendingWriteColumn,
        operation: PendingWriteOperation,
        valueToWrite: String?,
        expectedCurrentValue: String
    ) throws {
        guard let exercise = set.exercise else { throw WorkoutLoggingError.missingExercise }
        guard let session = exercise.session else { throw WorkoutLoggingError.missingSession }
        guard let week = session.week else { throw WorkoutLoggingError.missingWeek }
        guard let block = week.block else { throw WorkoutLoggingError.missingBlock }
        context.insert(
            PendingWrite(
                blockTab: block.tabName,
                week: week.number,
                day: session.dayNumber,
                exerciseName: exercise.name,
                setIndex: set.index,
                column: column,
                operation: operation,
                valueToWrite: valueToWrite,
                expectedCurrentValue: expectedCurrentValue
            )
        )
    }

    private func updateLastPerformed(for set: ExerciseSet, log: SetLog) throws {
        guard let exercise = set.exercise else { throw WorkoutLoggingError.missingExercise }
        guard let session = exercise.session else { throw WorkoutLoggingError.missingSession }
        guard let week = session.week else { throw WorkoutLoggingError.missingWeek }
        guard let block = week.block else { throw WorkoutLoggingError.missingBlock }

        try LastPerformedIndex(context: context).ingest([
            LastPerformedEntry(
                fullName: exercise.name,
                baseName: exercise.baseName,
                result: log,
                performedOn: session.date ?? Date(),
                source: "\(block.tabName) · W\(week.number) D\(session.dayNumber)"
            )
        ])
    }

    private func isFinalSet(_ set: ExerciseSet) -> Bool {
        let sets = set.exercise?.sets ?? []
        return set.index == (sets.map(\.index).max() ?? set.index)
    }

    private func rpeLabel(_ rpe: Double) -> String {
        rpe.rounded() == rpe ? String(Int(rpe)) : String(rpe)
    }
}
```

- [ ] **Step 8: Run all tests**

Run: `swift test 2>&1 | tail -30`
Expected: All tests PASS, including the existing `WorkoutStoreLoggingTests`.

- [ ] **Step 9: Commit**

```bash
git add WorkoutTracker/Progress/SessionProgressTracker.swift WorkoutTracker/Stores/WorkoutStore.swift WorkoutTrackerTests/SessionProgressTrackerTests.swift WorkoutTrackerTests/WorkoutStoreTests.swift
git commit -m "$(cat <<'EOF'
feat: add Move On, open exercises, and session navigation

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Theme + Block Overview View + Session Tile

**Files:**
- Modify: `WorkoutTracker/Theme.swift`
- Create: `WorkoutTracker/Views/SessionTile.swift`
- Create: `WorkoutTracker/Views/BlockOverviewView.swift`

- [ ] **Step 1: Add tile colors to Theme**

Add to `Theme.swift` below the existing `pillStroke` constant:

```swift
static let tileComplete = Color(red: 0.05, green: 0.25, blue: 0.15)
static let tileOpenExercises = Color(red: 0.35, green: 0.20, blue: 0.05)
static let tileUpcoming = Color(red: 0.06, green: 0.08, blue: 0.07)
static let tileDayFont: Font = .title3.weight(.bold)
static let tileWeekFont: Font = .caption2.weight(.medium)
static let tileHeight: CGFloat = 72
static let tileCornerRadius: CGFloat = 12
static let tileGridSpacing: CGFloat = 12
```

- [ ] **Step 2: Create SessionTile view**

Create `WorkoutTracker/Views/SessionTile.swift`:

```swift
import SwiftUI

struct SessionTile: View {
    let weekNumber: Int
    let dayNumber: Int
    let state: SessionTileState
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text("W\(weekNumber)")
                    .font(Theme.tileWeekFont)
                    .foregroundStyle(.secondary)
                Text("D\(dayNumber)")
                    .font(Theme.tileDayFont)
                    .foregroundStyle(state == .current ? Theme.accentDarkText : .primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Theme.tileHeight)
            .background(tileColor, in: .rect(cornerRadius: Theme.tileCornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Week \(weekNumber) Day \(dayNumber), \(accessibilityState)")
    }

    private var tileColor: Color {
        switch state {
        case .complete: Theme.tileComplete
        case .hasOpenExercises: Theme.tileOpenExercises
        case .current: Theme.accent
        case .upcoming: Theme.tileUpcoming
        }
    }

    private var accessibilityState: String {
        switch state {
        case .complete: "complete"
        case .hasOpenExercises: "has open exercises"
        case .current: "current session"
        case .upcoming: "upcoming"
        }
    }
}
```

- [ ] **Step 3: Create BlockOverviewView**

Create `WorkoutTracker/Views/BlockOverviewView.swift`:

```swift
import SwiftUI

struct BlockOverviewView: View {
    @Environment(WorkoutStore.self) private var workout
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.tileGridSpacing), count: 4)
    private let tracker = SessionProgressTracker()

    var body: some View {
        ScrollView {
            if let block = workout.block {
                LazyVGrid(columns: columns, spacing: Theme.tileGridSpacing) {
                    ForEach(sortedWeeks(block), id: \.persistentModelID) { week in
                        ForEach(sortedSessions(week), id: \.persistentModelID) { session in
                            SessionTile(
                                weekNumber: week.number,
                                dayNumber: session.dayNumber,
                                state: tracker.tileState(for: session, currentSession: workout.currentSession)
                            ) {
                                workout.show(week: week.number, day: session.dayNumber)
                                dismiss()
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle(workout.block?.tabName ?? "Block Overview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .background(Theme.gradient.ignoresSafeArea())
    }

    private func sortedWeeks(_ block: Block) -> [Week] {
        block.weeks.sorted { $0.number < $1.number }
    }

    private func sortedSessions(_ week: Week) -> [Session] {
        week.sessions.sorted { $0.dayNumber < $1.dayNumber }
    }
}
```

- [ ] **Step 4: Verify compilation**

Run: `xcodebuild -project WorkoutTracker.xcodeproj -scheme WorkoutTracker -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add WorkoutTracker/Theme.swift WorkoutTracker/Views/SessionTile.swift WorkoutTracker/Views/BlockOverviewView.swift
git commit -m "$(cat <<'EOF'
feat: add Block Overview grid with color-coded session tiles

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: SessionView Integration

**Files:**
- Modify: `WorkoutTracker/Views/SessionView.swift`

- [ ] **Step 1: Replace navigationTitle with tappable breadcrumb**

In `SessionView.swift`, replace:

```swift
.navigationTitle(breadcrumb)
```

with:

```swift
.navigationTitle("")
.navigationBarTitleDisplayMode(.inline)
.toolbar {
    ToolbarItem(placement: .principal) {
        NavigationLink {
            BlockOverviewView()
        } label: {
            HStack(spacing: 4) {
                Text(breadcrumb)
                Image(systemName: "square.grid.2x2")
                    .font(.caption2)
            }
            .font(.headline)
            .foregroundStyle(.primary)
        }
    }
}
```

- [ ] **Step 2: Add "Back to Current" banner**

Inside the `VStack(spacing: 0)` block in `SessionView`, after the `SyncStatusBanner`, add:

```swift
if !workout.isViewingLiveEdge {
    Button {
        workout.showCurrent()
    } label: {
        HStack {
            Image(systemName: "arrow.uturn.backward")
            Text("Back to Current Session")
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
        .padding()
        .background(Theme.accent.opacity(0.15), in: .rect(cornerRadius: Theme.cardCornerRadius))
    }
    .buttonStyle(.plain)
    .foregroundStyle(Theme.accent)
    .padding(.horizontal)
    .padding(.top, 4)
}
```

- [ ] **Step 3: Add Open Exercises section**

Inside the `LazyVStack`, after the `ForEach(session.exercises.sorted(...))` block, add:

```swift
if workout.isViewingLiveEdge, !workout.openExercises.isEmpty {
    VStack(alignment: .leading, spacing: 8) {
        Text("Open Exercises")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 8)

        ForEach(workout.openExercises, id: \.persistentModelID) { exercise in
            Button {
                if let week = exercise.session?.week?.number,
                   let day = exercise.session?.dayNumber {
                    workout.show(week: week, day: day)
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.baseName)
                            .font(.subheadline.weight(.semibold))
                        let pending = exercise.sets.filter { $0.state == .pending }.count
                        Text("\(pending) sets left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let day = exercise.session?.dayNumber,
                       let week = exercise.session?.week?.number {
                        Text("W\(week) D\(day)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.accent)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
            }
            .buttonStyle(.plain)
        }
    }
}
```

- [ ] **Step 4: Add Move On button**

Inside the `LazyVStack`, after the open exercises section, add:

```swift
if workout.isViewingLiveEdge, workout.canMoveOn {
    Button {
        workout.moveOn()
    } label: {
        HStack {
            Text("Move On")
                .font(.headline)
            Image(systemName: "arrow.right")
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
    .buttonStyle(.glass)
    .padding(.top, 8)
}
```

- [ ] **Step 5: Verify compilation**

Run: `xcodebuild -project WorkoutTracker.xcodeproj -scheme WorkoutTracker -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add WorkoutTracker/Views/SessionView.swift
git commit -m "$(cat <<'EOF'
feat: integrate breadcrumb nav, open exercises, and Move On into SessionView

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Verification

- [ ] **Step 1: Run the full test suite**

Run: `swift test 2>&1 | tail -30`
Expected: All package-level tests PASS.

- [ ] **Step 2: Run the full app build**

Run: `xcodebuild -project WorkoutTracker.xcodeproj -scheme WorkoutTracker -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Manual verification checklist**

Run the app in the simulator and verify:

- [ ] Session view shows breadcrumb in nav bar — tapping it pushes Block Overview
- [ ] Block Overview shows a 4×4 grid with color-coded tiles
- [ ] Tapping a tile navigates back to SessionView showing that session
- [ ] "Back to Current Session" banner appears when viewing a non-current session
- [ ] Tapping "Back to Current" returns to the live edge
- [ ] Open Exercises section appears below session exercises when past sessions have pending sets
- [ ] Tapping an open exercise navigates to its source session
- [ ] "Move On" button appears at the bottom when on the live edge
- [ ] Move On advances to the next session
- [ ] Move On persists across app relaunch
- [ ] Move On is not shown on the last session (W4 D4)
