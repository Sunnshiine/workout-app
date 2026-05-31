# Last Performed Index Backfill + Training Max Parsing (Plan 3 of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the Last Performed index into the sync layer so exercises show historical results, and parse Training Max values from the sheet so %1RM load suggestions work.

**Architecture:** Three sync-layer gaps closed: (1) `SheetParser` scans the block tab header area for a "Training Max" region and flows extracted values into the `Block` model; (2) after each sync, a pure extractor produces LP entries from the current parsed block and ingests them into the existing SwiftData `LastPerformedIndex`; (3) a background `Task` backfills LP entries from older block tabs when current-block exercises lack history (ADR 0002).

**Tech Stack:** Swift 6, iOS 26, SwiftData, Swift Testing, Google Sheets REST (read-only for backfill).

**Reference docs:** spec `docs/superpowers/specs/2026-05-24-high-level-app-design.md`; glossary `CONTEXT.md`; ADRs `docs/adr/0001..0004`; PRD issue #1; redesign PRD issue #13.

---

## Current Repo State To Preserve

- Plan 1 and Plan 2 are fully implemented. Do not repeat prior setup work.
- All LP/LoadSuggestion engines exist and are tested. `LastPerformedIndex`, `LastPerformedEntry`, `LoadSuggestionEngine`, `SmartValuePillsForm`, `ActiveSetCard`, `LastPerformedCard` — all wired and rendering.
- `WorkoutStore.log()` already calls `updateLastPerformed()` for incremental LP updates during live logging.
- Current visual language: Liquid Glass cards, antique-gold accent, mint active-set system. Do not touch Views.
- Test runner: `swift test` for package-level tests; `xcodebuild -project WorkoutTracker.xcodeproj -scheme WorkoutTracker -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` for full app build.

## Sheet Layout Context

The "Training Max" area lives above the week sections. Its position varies across blocks:
- Blocks 23–25: header `"Training Max"` at column G (0-based 6), row 7 (0-based 6). Labels at column E, values at column G.
- Blocks 26–27: header `"Training Max"` at column E (0-based 4), row 6 (0-based 5). Labels at column C, values at column E.
- **Consistent pattern:** labels are always 2 columns left of the TM value column. Parser must scan dynamically.

## File Structure

```
WorkoutTracker/
  Parsing/
    SheetParser.swift              # add parseTrainingMax(); add TM fields to ParsedBlockModel
    BlockBuilder.swift             # pass TM values through to Block
    BlockTabSelector.swift         # add sortedHistoricalTabs()
  Progress/
    LastPerformedExtractor.swift   # new — pure function: ParsedBlockModel → [LastPerformedEntry]
  Stores/
    SyncCoordinator.swift          # LP ingestion after sync + background historical backfill
WorkoutTrackerTests/
  TrainingMaxParserTests.swift     # new
  LastPerformedExtractorTests.swift # new
  BackfillTests.swift              # new
```

---

## Task 1: Training Max Parsing

**Files:**
- Modify: `WorkoutTracker/Parsing/SheetParser.swift:200-203` (ParsedBlockModel) and `:209-229` (SheetParser.parse)
- Modify: `WorkoutTracker/Parsing/BlockBuilder.swift:5`
- Test: `WorkoutTrackerTests/TrainingMaxParserTests.swift` (new)

- [ ] **Step 1: Write the failing tests**

Create `WorkoutTrackerTests/TrainingMaxParserTests.swift`:

```swift
import Testing

@testable import WorkoutTracker

@Test func parsesTrainingMaxFromBlockHeaderArea() {
    let grid = gridFromA1(
        [
            "E6": "Training Max",
            "C7": "Squat", "E7": "315",
            "C8": "Bench Press", "E8": "225",
            "C9": "Deadlift", "E9": "405",
            "C12": "Day 1", "S12": "Day 2"
        ],
        rows: 20,
        cols: 30
    )

    let tm = parseTrainingMax(from: grid)

    #expect(tm.squat == 315)
    #expect(tm.bench == 225)
    #expect(tm.deadlift == 405)
}

@Test func parsesTrainingMaxAtAlternatePosition() {
    let grid = gridFromA1(
        [
            "G7": "Training Max",
            "E8": "Squat", "G8": "300",
            "E9": "Bench Press", "G9": "215",
            "E10": "Deadlift", "G10": "385",
            "C12": "Day 1", "S12": "Day 2"
        ],
        rows: 20,
        cols: 30
    )

    let tm = parseTrainingMax(from: grid)

    #expect(tm.squat == 300)
    #expect(tm.bench == 215)
    #expect(tm.deadlift == 385)
}

@Test func returnsNilTrainingMaxWhenHeaderMissing() {
    let grid = gridFromA1(
        ["C12": "Day 1", "S12": "Day 2"],
        rows: 20,
        cols: 30
    )

    let tm = parseTrainingMax(from: grid)

    #expect(tm.squat == nil)
    #expect(tm.bench == nil)
    #expect(tm.deadlift == nil)
}

@Test func returnsNilTrainingMaxWhenValuesBlank() {
    let grid = gridFromA1(
        [
            "E6": "Training Max",
            "C7": "Squat", "E7": "",
            "C8": "Bench Press",
            "C9": "Deadlift"
        ],
        rows: 15,
        cols: 10
    )

    let tm = parseTrainingMax(from: grid)

    #expect(tm.squat == nil)
    #expect(tm.bench == nil)
    #expect(tm.deadlift == nil)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TrainingMaxParser 2>&1 | tail -5`
Expected: compilation error — `parseTrainingMax` not defined.

- [ ] **Step 3: Add TM fields to ParsedBlockModel**

In `WorkoutTracker/Parsing/SheetParser.swift`, change:

```swift
struct ParsedBlockModel {
    var tabName: String
    var weeks: [ParsedWeek]
}
```

to:

```swift
struct ParsedBlockModel {
    var tabName: String
    var squatTM: Double?
    var benchTM: Double?
    var deadliftTM: Double?
    var weeks: [ParsedWeek]
}
```

Default values are `nil`, so existing callers (BlockBuilderTests, etc.) still compile via Swift's memberwise init.

- [ ] **Step 4: Implement parseTrainingMax**

Add to `WorkoutTracker/Parsing/SheetParser.swift`, above `SheetParser`:

```swift
func parseTrainingMax(
    from grid: SheetGrid
) -> (squat: Double?, bench: Double?, deadlift: Double?) {
    let scanRows = min(15, grid.count)
    for r in 0..<scanRows {
        for c in 0..<grid[r].count {
            guard grid[r][c].trimmed.caseInsensitiveCompare("Training Max") == .orderedSame else {
                continue
            }
            let labelCol = c - 2
            guard labelCol >= 0 else { return (nil, nil, nil) }
            var squat: Double?
            var bench: Double?
            var deadlift: Double?
            for offset in 1...3 {
                let label = grid.cell(row: r + offset, col: labelCol).trimmed
                let value = Double(grid.cell(row: r + offset, col: c).trimmed)
                if label.caseInsensitiveCompare("Squat") == .orderedSame {
                    squat = value
                } else if label.caseInsensitiveCompare("Bench Press") == .orderedSame {
                    bench = value
                } else if label.caseInsensitiveCompare("Deadlift") == .orderedSame {
                    deadlift = value
                }
            }
            return (squat, bench, deadlift)
        }
    }
    return (nil, nil, nil)
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter TrainingMaxParser 2>&1 | tail -5`
Expected: all 4 tests PASS.

- [ ] **Step 6: Wire into SheetParser.parse() and BlockBuilder.makeBlock()**

In `WorkoutTracker/Parsing/SheetParser.swift`, inside `SheetParser.parse()`, change:

```swift
return ParsedBlock(block: ParsedBlockModel(tabName: tabName, weeks: weeks), warnings: warnings)
```

to:

```swift
let tm = parseTrainingMax(from: grid)
return ParsedBlock(
    block: ParsedBlockModel(
        tabName: tabName,
        squatTM: tm.squat,
        benchTM: tm.bench,
        deadliftTM: tm.deadlift,
        weeks: weeks
    ),
    warnings: warnings
)
```

In `WorkoutTracker/Parsing/BlockBuilder.swift`, change:

```swift
let block = Block(tabName: p.tabName, squatTM: nil, benchTM: nil, deadliftTM: nil)
```

to:

```swift
let block = Block(tabName: p.tabName, squatTM: p.squatTM, benchTM: p.benchTM, deadliftTM: p.deadliftTM)
```

- [ ] **Step 7: Run all tests**

Run: `swift test 2>&1 | tail -10`
Expected: all tests PASS (including existing SheetParser and BlockBuilder tests).

- [ ] **Step 8: Commit**

```bash
git add WorkoutTrackerTests/TrainingMaxParserTests.swift WorkoutTracker/Parsing/SheetParser.swift WorkoutTracker/Parsing/BlockBuilder.swift
git commit -m "$(cat <<'EOF'
feat: parse Training Max values from sheet grid

Scan the block tab's header area for a "Training Max" cell and extract
Squat/Bench Press/Deadlift values. The TM position varies across blocks
so the parser scans dynamically. Values flow through ParsedBlockModel
into the persisted Block model for %1RM load suggestions.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: LP Extraction Helper

**Files:**
- Create: `WorkoutTracker/Progress/LastPerformedExtractor.swift`
- Test: `WorkoutTrackerTests/LastPerformedExtractorTests.swift` (new)

- [ ] **Step 1: Write the failing tests**

Create `WorkoutTrackerTests/LastPerformedExtractorTests.swift`:

```swift
import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
@Test func extractsLPEntryFromLoggedExercise() throws {
    let block = ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            ParsedWeek(
                number: 2,
                days: [
                    ParsedSession(
                        dayNumber: 3,
                        date: Date(timeIntervalSinceReferenceDate: 500),
                        exercises: [
                            ParsedExercise(
                                name: "2-3:1:0 BB RDL",
                                baseName: "BB RDL",
                                cadence: "2-3:1:0",
                                coachNote: nil,
                                sets: [
                                    ParsedSet(
                                        index: 0,
                                        prescribedReps: "8",
                                        prescribedLoad: "RPE7",
                                        percentOneRM: nil,
                                        setLog: SetLog(weight: .pounds(185), reps: 8, rpe: 7)
                                    ),
                                    ParsedSet(
                                        index: 1,
                                        prescribedReps: "8",
                                        prescribedLoad: "RPE8",
                                        percentOneRM: nil,
                                        setLog: SetLog(weight: .pounds(185), reps: 7, rpe: 8)
                                    )
                                ]
                            )
                        ]
                    )
                ]
            )
        ]
    )

    let entries = extractLastPerformedEntries(from: block)

    #expect(entries.count == 1)
    let entry = try #require(entries.first)
    #expect(entry.fullName == "2-3:1:0 BB RDL")
    #expect(entry.baseName == "BB RDL")
    #expect(entry.result == SetLog(weight: .pounds(185), reps: 7, rpe: 8))
    #expect(entry.source == "Block 27 · W2 D3")
}

@MainActor
@Test func extractsNoEntriesWhenNothingLogged() {
    let block = ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            ParsedWeek(
                number: 1,
                days: [
                    ParsedSession(
                        dayNumber: 1,
                        date: nil,
                        exercises: [
                            ParsedExercise(
                                name: "Squat",
                                baseName: "Squat",
                                cadence: nil,
                                coachNote: nil,
                                sets: [
                                    ParsedSet(
                                        index: 0,
                                        prescribedReps: "5",
                                        prescribedLoad: "RPE8",
                                        percentOneRM: nil
                                    )
                                ]
                            )
                        ]
                    )
                ]
            )
        ]
    )

    let entries = extractLastPerformedEntries(from: block)

    #expect(entries.isEmpty)
}

@MainActor
@Test func extractsLatestSessionPerExerciseAcrossWeeks() throws {
    let block = ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            ParsedWeek(
                number: 1,
                days: [
                    ParsedSession(
                        dayNumber: 1,
                        date: Date(timeIntervalSinceReferenceDate: 100),
                        exercises: [
                            ParsedExercise(
                                name: "Squat",
                                baseName: "Squat",
                                cadence: nil,
                                coachNote: nil,
                                sets: [
                                    ParsedSet(
                                        index: 0,
                                        prescribedReps: "5",
                                        prescribedLoad: "RPE8",
                                        percentOneRM: nil,
                                        setLog: SetLog(weight: .pounds(275), reps: 5, rpe: 7)
                                    )
                                ]
                            )
                        ]
                    )
                ]
            ),
            ParsedWeek(
                number: 2,
                days: [
                    ParsedSession(
                        dayNumber: 1,
                        date: Date(timeIntervalSinceReferenceDate: 200),
                        exercises: [
                            ParsedExercise(
                                name: "Squat",
                                baseName: "Squat",
                                cadence: nil,
                                coachNote: nil,
                                sets: [
                                    ParsedSet(
                                        index: 0,
                                        prescribedReps: "5",
                                        prescribedLoad: "RPE8",
                                        percentOneRM: nil,
                                        setLog: SetLog(weight: .pounds(295), reps: 5, rpe: 8)
                                    )
                                ]
                            )
                        ]
                    )
                ]
            )
        ]
    )

    let entries = extractLastPerformedEntries(from: block)

    #expect(entries.count == 1)
    let entry = try #require(entries.first)
    #expect(entry.result == SetLog(weight: .pounds(295), reps: 5, rpe: 8))
    #expect(entry.source == "Block 27 · W2 D1")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LastPerformedExtractor 2>&1 | tail -5`
Expected: compilation error — `extractLastPerformedEntries` not defined.

- [ ] **Step 3: Create the extractor**

Create `WorkoutTracker/Progress/LastPerformedExtractor.swift`:

```swift
import Foundation

@MainActor
func extractLastPerformedEntries(from block: ParsedBlockModel) -> [LastPerformedEntry] {
    var latest: [String: (entry: LastPerformedEntry, date: Date)] = [:]
    for week in block.weeks {
        for day in week.days {
            let date = day.date ?? Date.distantPast
            let source = "\(block.tabName) · W\(week.number) D\(day.dayNumber)"
            for exercise in day.exercises {
                guard
                    let lastLogged = exercise.sets.last(where: { $0.state == .logged }),
                    let log = lastLogged.setLog
                else { continue }
                if let existing = latest[exercise.name], existing.date > date { continue }
                latest[exercise.name] = (
                    LastPerformedEntry(
                        fullName: exercise.name,
                        baseName: exercise.baseName,
                        result: log,
                        performedOn: date,
                        source: source
                    ),
                    date
                )
            }
        }
    }
    return latest.values.map(\.entry)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LastPerformedExtractor 2>&1 | tail -5`
Expected: all 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add WorkoutTracker/Progress/LastPerformedExtractor.swift WorkoutTrackerTests/LastPerformedExtractorTests.swift
git commit -m "$(cat <<'EOF'
feat: add LP entry extraction from parsed blocks

Pure helper that walks a ParsedBlockModel and produces one
LastPerformedEntry per exercise with logged sets, keeping the latest
session per exercise name.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Current Block LP Ingestion on Sync

**Files:**
- Modify: `WorkoutTracker/Stores/SyncCoordinator.swift:87` (after replacePersistedBlock)
- Test: `WorkoutTrackerTests/SyncCoordinatorTests.swift` (add test)

- [ ] **Step 1: Write the failing test**

Add to `WorkoutTrackerTests/SyncCoordinatorTests.swift`:

```swift
@MainActor
@Test func syncIngestsLPEntriesFromCurrentBlock() async throws {
    let container = try ModelContainer(
        for: Block.self, PendingWrite.self, LastPerformedEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "C13": "5/19/2026",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Squat", "D15": "1", "F15": "5", "H15": "RPE8",
            "K16": "315x5@8"
        ],
        rows: 20,
        cols: 60
    )
    let client = StubClient(titles: ["Block 27"], grid: grid)
    let sync = SyncCoordinator(client: client, context: container.mainContext)

    await sync.sync(spreadsheetId: "sid")

    let entries = try container.mainContext.fetch(FetchDescriptor<LastPerformedEntry>())
    #expect(entries.count == 1)
    #expect(entries[0].fullName == "Squat")
    #expect(entries[0].result == SetLog(weight: .pounds(315), reps: 5, rpe: 8))
    #expect(entries[0].source == "Block 27 · W1 D1")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter syncIngestsLPEntries 2>&1 | tail -5`
Expected: FAIL — `entries.count == 0` (LP ingestion not wired yet).

- [ ] **Step 3: Wire LP ingestion into SyncCoordinator.sync()**

In `WorkoutTracker/Stores/SyncCoordinator.swift`, inside `sync()`, add these lines immediately after the `replacePersistedBlock` call (line 87) and before the `if case .conflict` check:

```swift
        let lpEntries = extractLastPerformedEntries(from: parsed.block)
        if !lpEntries.isEmpty {
            try? LastPerformedIndex(context: context).ingest(lpEntries)
        }
```

The surrounding code should read:

```swift
            replacePersistedBlock(with: BlockBuilder.makeBlock(from: parsed.block))
            let lpEntries = extractLastPerformedEntries(from: parsed.block)
            if !lpEntries.isEmpty {
                try? LastPerformedIndex(context: context).ingest(lpEntries)
            }
            if case .conflict = stateAfterFlush {
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter syncIngestsLPEntries 2>&1 | tail -5`
Expected: PASS.

Run: `swift test 2>&1 | tail -10`
Expected: all tests PASS (existing sync tests unaffected).

- [ ] **Step 5: Commit**

```bash
git add WorkoutTracker/Stores/SyncCoordinator.swift WorkoutTrackerTests/SyncCoordinatorTests.swift
git commit -m "$(cat <<'EOF'
feat: ingest LP entries from current block on sync

After persisting the block, extract logged set results and ingest them
into the Last Performed index so exercises show their most recent
result without waiting for the athlete to re-log.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Historical Block Backfill

**Files:**
- Modify: `WorkoutTracker/Parsing/BlockTabSelector.swift` (add sortedHistoricalTabs)
- Modify: `WorkoutTracker/Stores/SyncCoordinator.swift` (add backfill method + Task launch)
- Test: `WorkoutTrackerTests/BackfillTests.swift` (new)

- [ ] **Step 1: Write the failing test for sortedHistoricalTabs**

Add to `WorkoutTrackerTests/BlockTabSelectorTests.swift`:

```swift
@Test func sortsHistoricalTabsByBlockNumberDescending() {
    let tabs = sortedHistoricalTabs(
        from: ["Intro", "Block - 23", "Block - 24", "Block - 25", "Block - 26", "Block 27"],
        excluding: "Block 27"
    )

    #expect(tabs == ["Block - 26", "Block - 25", "Block - 24", "Block - 23"])
}

@Test func returnsEmptyWhenNoHistoricalTabs() {
    let tabs = sortedHistoricalTabs(
        from: ["Intro", "Block 27"],
        excluding: "Block 27"
    )

    #expect(tabs.isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter sortsHistoricalTabs 2>&1 | tail -5`
Expected: compilation error — `sortedHistoricalTabs` not defined.

- [ ] **Step 3: Implement sortedHistoricalTabs**

Add to `WorkoutTracker/Parsing/BlockTabSelector.swift`:

```swift
func sortedHistoricalTabs(from titles: [String], excluding current: String) -> [String] {
    let regex = /^Block\s*-?\s*(\d+)$/
    var pairs: [(title: String, number: Int)] = []
    for title in titles where title != current {
        if let m = title.wholeMatch(of: regex), let n = Int(m.1) {
            pairs.append((title, n))
        }
    }
    pairs.sort { $0.number > $1.number }
    return pairs.map(\.title)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "sortsHistoricalTabs|returnsEmptyWhenNoHistorical" 2>&1 | tail -5`
Expected: PASS.

- [ ] **Step 5: Write the backfill integration test**

Create `WorkoutTrackerTests/BackfillTests.swift`:

```swift
import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

private final class MultiTabStubClient: SheetsClient, @unchecked Sendable {
    let titles: [String]
    let grids: [String: SheetGrid]
    private(set) var fetchedTabs: [String] = []

    init(titles: [String], grids: [String: SheetGrid]) {
        self.titles = titles
        self.grids = grids
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] { titles }
    func fetchTab(spreadsheetId: String, tabName: String) async throws -> SheetGrid {
        fetchedTabs.append(tabName)
        return grids[tabName] ?? []
    }
    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}
}

@MainActor
private func backfillContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Block.self, PendingWrite.self, LastPerformedEntry.self,
        configurations: ModelConfiguration(
            "backfill-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
}

@MainActor
@Test func backfillPopulatesLPFromHistoricalBlock() async throws {
    let container = try backfillContainer()

    let block27Grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "C13": "5/19/2026",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Squat", "D15": "1", "F15": "5", "H15": "RPE8",
            "K16": "315x5@8",
            "C18": "BB RDL", "D18": "1", "F18": "8", "H18": "RPE7"
        ],
        rows: 25,
        cols: 60
    )

    let block26Grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "C13": "5/5/2026",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "BB RDL", "D15": "1", "F15": "8", "H15": "RPE7",
            "K16": "185x8@7"
        ],
        rows: 20,
        cols: 60
    )

    let titles = ["Intro", "Block - 26", "Block 27"]
    let client = MultiTabStubClient(
        titles: titles,
        grids: ["Block 27": block27Grid, "Block - 26": block26Grid]
    )
    let sync = SyncCoordinator(client: client, context: container.mainContext)

    let parsed = SheetParser().parse(grid: block27Grid, tabName: "Block 27")
    await sync.backfillLastPerformed(
        spreadsheetId: "sid",
        currentTab: "Block 27",
        allTitles: titles,
        currentBlock: parsed.block
    )

    let index = LastPerformedIndex(context: container.mainContext)
    let match = index.lookup(exerciseName: "BB RDL", baseName: "BB RDL")
    #expect(match != nil)
    #expect(match?.result == SetLog(weight: .pounds(185), reps: 8, rpe: 7))
    #expect(match?.source == "Block - 26 · W1 D1")
    withExtendedLifetime(container) {}
}

@MainActor
@Test func backfillSkipsWhenAllExercisesCovered() async throws {
    let container = try backfillContainer()
    let context = container.mainContext

    try LastPerformedIndex(context: context).ingest([
        LastPerformedEntry(
            fullName: "Squat",
            baseName: "Squat",
            result: SetLog(weight: .pounds(315), reps: 5, rpe: 8),
            performedOn: Date(timeIntervalSinceReferenceDate: 500),
            source: "Block 27 · W1 D1"
        )
    ])

    let titles = ["Intro", "Block - 26", "Block 27"]
    let client = MultiTabStubClient(
        titles: titles,
        grids: ["Block - 26": gridFromA1([:], rows: 5, cols: 5)]
    )
    let sync = SyncCoordinator(client: client, context: context)

    let currentBlock = ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            ParsedWeek(
                number: 1,
                days: [
                    ParsedSession(
                        dayNumber: 1,
                        date: nil,
                        exercises: [
                            ParsedExercise(
                                name: "Squat",
                                baseName: "Squat",
                                cadence: nil,
                                coachNote: nil,
                                sets: [
                                    ParsedSet(
                                        index: 0,
                                        prescribedReps: "5",
                                        prescribedLoad: "RPE8",
                                        percentOneRM: nil
                                    )
                                ]
                            )
                        ]
                    )
                ]
            )
        ]
    )

    await sync.backfillLastPerformed(
        spreadsheetId: "sid",
        currentTab: "Block 27",
        allTitles: titles,
        currentBlock: currentBlock
    )

    #expect(client.fetchedTabs.isEmpty)
    withExtendedLifetime(container) {}
}

@MainActor
@Test func backfillStopsAfterCoverageComplete() async throws {
    let container = try backfillContainer()

    let block27Grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Lateral Raises", "D15": "1", "F15": "12", "H15": "RPE9"
        ],
        rows: 20,
        cols: 60
    )

    let block26Grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "C13": "5/5/2026",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Lateral Raises", "D15": "1", "F15": "12", "H15": "RPE9",
            "K16": "25x12@8"
        ],
        rows: 20,
        cols: 60
    )

    let block25Grid = gridFromA1([:], rows: 5, cols: 5)

    let titles = ["Block - 25", "Block - 26", "Block 27"]
    let client = MultiTabStubClient(
        titles: titles,
        grids: [
            "Block 27": block27Grid,
            "Block - 26": block26Grid,
            "Block - 25": block25Grid
        ]
    )
    let sync = SyncCoordinator(client: client, context: container.mainContext)

    let parsed = SheetParser().parse(grid: block27Grid, tabName: "Block 27")
    await sync.backfillLastPerformed(
        spreadsheetId: "sid",
        currentTab: "Block 27",
        allTitles: titles,
        currentBlock: parsed.block
    )

    #expect(client.fetchedTabs == ["Block - 26"])
    withExtendedLifetime(container) {}
}
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `swift test --filter Backfill 2>&1 | tail -5`
Expected: compilation error — `backfillLastPerformed` not defined on SyncCoordinator.

- [ ] **Step 7: Implement the backfill method**

Add to `WorkoutTracker/Stores/SyncCoordinator.swift`, after the `sync()` method:

```swift
    func backfillLastPerformed(
        spreadsheetId: String,
        currentTab: String,
        allTitles: [String],
        currentBlock: ParsedBlockModel
    ) async {
        let tabs = sortedHistoricalTabs(from: allTitles, excluding: currentTab)
        guard !tabs.isEmpty else { return }

        let exerciseIds = uniqueExerciseIdentifiers(from: currentBlock)
        let index = LastPerformedIndex(context: context)

        guard exerciseIds.contains(where: {
            index.lookup(exerciseName: $0.fullName, baseName: $0.baseName) == nil
        }) else { return }

        for tab in tabs {
            do {
                let grid = try await client.fetchTab(spreadsheetId: spreadsheetId, tabName: tab)
                let parsed = SheetParser().parse(grid: grid, tabName: tab)
                let entries = extractLastPerformedEntries(from: parsed.block)
                if !entries.isEmpty {
                    try index.ingest(entries)
                }
                let allCovered = !exerciseIds.contains(where: {
                    index.lookup(exerciseName: $0.fullName, baseName: $0.baseName) == nil
                })
                if allCovered { break }
            } catch {
                continue
            }
        }
    }

    private func uniqueExerciseIdentifiers(
        from block: ParsedBlockModel
    ) -> [(fullName: String, baseName: String)] {
        var seen = Set<String>()
        var result: [(fullName: String, baseName: String)] = []
        for week in block.weeks {
            for day in week.days {
                for exercise in day.exercises where seen.insert(exercise.name).inserted {
                    result.append((exercise.name, exercise.baseName))
                }
            }
        }
        return result
    }
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `swift test --filter Backfill 2>&1 | tail -5`
Expected: all 3 backfill tests PASS.

- [ ] **Step 9: Wire backfill Task into sync()**

In `WorkoutTracker/Stores/SyncCoordinator.swift`, inside `sync()`, add after the `print("[Sync] Done, state: \(state)")` line and before the closing `} catch`:

```swift
            Task {
                await self.backfillLastPerformed(
                    spreadsheetId: spreadsheetId,
                    currentTab: tab,
                    allTitles: titles,
                    currentBlock: parsed.block
                )
            }
```

- [ ] **Step 10: Run all tests**

Run: `swift test 2>&1 | tail -10`
Expected: all tests PASS.

- [ ] **Step 11: Commit**

```bash
git add WorkoutTracker/Parsing/BlockTabSelector.swift WorkoutTracker/Stores/SyncCoordinator.swift WorkoutTrackerTests/BlockTabSelectorTests.swift WorkoutTrackerTests/BackfillTests.swift
git commit -m "$(cat <<'EOF'
feat: backfill Last Performed index from historical blocks

After syncing the current block, a background Task scans older block
tabs in descending order to fill LP gaps for exercises that lack
history. Stops early when all current-block exercises are covered.
Network errors are silently ignored per ADR 0002.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Final Verification

**Files:** none (read-only verification)

- [ ] **Step 1: Run the full test suite**

Run: `swift test 2>&1 | tail -15`
Expected: all tests PASS with zero failures.

- [ ] **Step 2: Build the app target**

Run: `xcodebuild -project WorkoutTracker.xcodeproj -scheme WorkoutTracker -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Verify PRD coverage**

Confirm these user stories are now fully wired end-to-end:

| Story | Status |
|---|---|
| 6: See Last Performed per exercise | LP index now populated from sync + backfill |
| 7: Cadence-aware LP lookup | `LastPerformedIndex.lookup()` two-tier matching (pre-existing) |
| 8: LP skips Skipped occurrences | extractor only emits `.logged` sets (by design) |
| 9: Drop X% load suggestions | `LoadSuggestionEngine` (pre-existing, wired) |
| 10: %1RM load suggestions | TM parsing now flows into Block → ActiveSetCard → SmartValuePillsForm |
| 11: Suggestions as overridable pre-fills | `SmartValuePillsForm.initialWeightText()` (pre-existing) |
