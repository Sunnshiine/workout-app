# Logging + Verified Write-Back Implementation Plan (Plan 2 of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the athlete log, edit, delete, and skip Sets locally, queue verified Google Sheets writes, and flush those writes without overwriting unexpected Sheet content.

**Architecture:** This extends the Plan 1 read path with a local-first write path. `WorkoutStore` owns optimistic Set mutations and creates `PendingWrite` rows; `SyncCoordinator` owns queue flushing; `SheetWriter` resolves live Sheet targets by scanning headers and exercise anchors before every write. SwiftUI stays thin: glass exercise cards render compact per-set controls and call store methods.

**Tech Stack:** Swift 6, iOS 26, SwiftUI, SwiftData, Swift Testing, Google Sheets REST values `batchUpdate`, `@Observable` stores.

**Reference docs:** spec `docs/superpowers/specs/2026-05-24-high-level-app-design.md`; glossary `CONTEXT.md`; ADRs `docs/adr/0001..0003`; PRD issue #1; redesign issues #3-#10; manual testing notes `docs/TESTING.md`.

---

## Current Repo State To Preserve

- The app scaffold exists now. Do not repeat Plan 1's manual Xcode project setup.
- Current visual language is the closed-issue redesign: near-flat obsidian background, Liquid Glass cards, antique-gold accent, `SetChip` without `S1`/`S2` prefixes, and a custom glass empty state.
- The parser already splits comma-separated reps/load values per Set. Preserve those tests and behavior.
- Use `swift test` for package-level engines/stores and `xcodebuild -project WorkoutTracker.xcodeproj -scheme WorkoutTracker -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` for app/view verification.

## Safety Assumptions

- Follow the PRD and handoff contract: **anchor-row Notes are protected Coach Notes**; Set Logs and `skip` writes target the Notes column on continuation rows beneath the exercise anchor.
- For a Set at index `0`, the Notes target row is `anchorRow + 1`; for index `1`, `anchorRow + 2`; and so on. If that row reaches the next exercise anchor or the week section boundary, the writer returns `.setRowNotFound` and marks the pending write as conflict instead of guessing.
- The local Block 27 snapshot contains old compact values in some anchor-row Notes cells, such as `K15 = "25x12, 12"`. This plan intentionally does not write to those anchor Notes cells.
- Last Set RPE writes target the `Last set RPE` column on the exercise anchor row.
- Plan 3 owns Last Performed and Load Suggestions. This plan only provides the logging data those later engines will consume.

## File Structure

```
WorkoutTracker/
  Models/
    SetLog.swift                       # add parser/normalizer for log input
    Exercise.swift                     # add ExerciseSet.setLog computed storage
    PendingWrite.swift                 # new SwiftData FIFO write queue model
  Parsing/
    SheetParser.swift                  # parse continuation-row Set Logs and skip markers
    BlockBuilder.swift                 # persist parsed Set state/log data
    SheetGrid.swift                    # add A1 rendering helpers
  Sheets/
    SheetsClient.swift                 # add updateCells protocol surface
    GoogleSheetsClient.swift           # values:batchUpdate implementation
    SheetWriter.swift                  # target resolution + verify-before-write
  Stores/
    WorkoutStore.swift                 # optimistic log/edit/delete/skip mutations
    SyncCoordinator.swift              # flush queue before sync and on demand
  Views/
    SetLogEditor.swift                 # compact native per-set logging controls
    ExerciseCard.swift                 # render SetLogEditor below each SetChip
    SyncStatusBanner.swift             # pending/offline/conflict banner
    SessionView.swift                  # pass store actions into cards and show status
  WorkoutTrackerApp.swift              # include PendingWrite in ModelContainer
WorkoutTrackerTests/
  PendingWriteTests.swift
  SetLogParsingTests.swift
  SheetParserLogTests.swift
  SheetA1Tests.swift
  SheetWriterTests.swift
  WorkoutStoreLoggingTests.swift
  SyncCoordinatorWriteTests.swift
```

---

## Task 1: Parse and Persist `SetLog`

**Files:**
- Modify: `WorkoutTracker/Models/SetLog.swift`
- Modify: `WorkoutTracker/Models/Exercise.swift`
- Test: `WorkoutTrackerTests/SetLogParsingTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import WorkoutTracker

@Test func parsesFormattedWeightedSetLog() throws {
    let log = try #require(SetLog(formatted: "185x7@6.5"))
    #expect(log.weight == .pounds(185))
    #expect(log.reps == 7)
    #expect(log.rpe == 6.5)
    #expect(log.formatted == "185x7@6.5")
}

@Test func parsesFormattedBodyweightSetLog() throws {
    let log = try #require(SetLog(formatted: "BWx12@7"))
    #expect(log.weight == .bodyweight)
    #expect(log.reps == 12)
    #expect(log.rpe == 7)
    #expect(log.formatted == "BWx12@7")
}

@Test func rejectsMalformedSetLogStrings() {
    #expect(SetLog(formatted: "") == nil)
    #expect(SetLog(formatted: "185@7") == nil)
    #expect(SetLog(formatted: "185xseven@7") == nil)
    #expect(SetLog(formatted: "185x7@hard") == nil)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SetLogParsingTests`

Expected: FAIL because `SetLog.init(formatted:)` does not exist.

- [ ] **Step 3: Add parsing to `SetLog.swift`**

```swift
import Foundation

enum SetState: String, Codable, Sendable {
    case pending, logged, skipped
}

enum Weight: Codable, Sendable, Equatable {
    case bodyweight
    case pounds(Double)

    var label: String {
        switch self {
        case .bodyweight: return "BW"
        case .pounds(let v):
            return v.rounded() == v ? String(Int(v)) : String(v)
        }
    }
}

struct SetLog: Codable, Sendable, Equatable {
    var weight: Weight
    var reps: Int
    var rpe: Double

    init(weight: Weight, reps: Int, rpe: Double) {
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
    }

    init?(formatted raw: String) {
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "@", maxSplits: 1)
        guard parts.count == 2, let rpe = Double(parts[1]) else { return nil }
        let left = parts[0].split(separator: "x", maxSplits: 1)
        guard left.count == 2, let reps = Int(left[1]) else { return nil }

        let weightText = String(left[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let weight: Weight
        if weightText.caseInsensitiveCompare("BW") == .orderedSame {
            weight = .bodyweight
        } else if let pounds = Double(weightText) {
            weight = .pounds(pounds)
        } else {
            return nil
        }

        self.init(weight: weight, reps: reps, rpe: rpe)
    }

    var formatted: String {
        let rpeLabel = rpe.rounded() == rpe ? String(Int(rpe)) : String(rpe)
        return "\(weight.label)x\(reps)@\(rpeLabel)"
    }
}
```

- [ ] **Step 4: Add `ExerciseSet.setLog` storage to `Exercise.swift`**

```swift
@Model
final class ExerciseSet {
    var index: Int
    var prescribedReps: String
    var prescribedLoad: String
    var percentOneRM: String?
    var stateRaw: String
    var setLogData: Data?
    var exercise: Exercise?

    var state: SetState {
        get { SetState(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }

    var setLog: SetLog? {
        get {
            guard let setLogData else { return nil }
            return try? JSONDecoder().decode(SetLog.self, from: setLogData)
        }
        set {
            setLogData = try? newValue.map { try JSONEncoder().encode($0) }
        }
    }

    init(index: Int, prescribedReps: String, prescribedLoad: String, percentOneRM: String?, state: SetState) {
        self.index = index
        self.prescribedReps = prescribedReps
        self.prescribedLoad = prescribedLoad
        self.percentOneRM = percentOneRM
        self.stateRaw = state.rawValue
    }
}
```

- [ ] **Step 5: Add a persistence test for `ExerciseSet.setLog`**

Append to `WorkoutTrackerTests/SetLogParsingTests.swift`:

```swift
import SwiftData

@MainActor
@Test func exerciseSetStoresSetLogAsCodableData() throws {
    let set = ExerciseSet(index: 0, prescribedReps: "7", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending)
    set.setLog = SetLog(weight: .pounds(185), reps: 7, rpe: 8)
    set.state = .logged

    #expect(set.setLog?.formatted == "185x7@8")
    #expect(set.state == .logged)
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter SetLogParsingTests`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add WorkoutTracker/Models/SetLog.swift WorkoutTracker/Models/Exercise.swift WorkoutTrackerTests/SetLogParsingTests.swift
git commit -m "feat: parse and persist set logs"
```

---

## Task 2: Parse Existing Sheet Logs From Continuation Rows

**Files:**
- Modify: `WorkoutTracker/Parsing/SheetParser.swift`
- Modify: `WorkoutTracker/Parsing/BlockBuilder.swift`
- Test: `WorkoutTrackerTests/SheetParserLogTests.swift`

- [ ] **Step 1: Write the failing parser tests**

```swift
import Testing
@testable import WorkoutTracker

@Test func parsesSetLogsFromNotesContinuationRows() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
            "C15": "Squat", "D15": "2", "F15": "5", "H15": "RPE 8", "K15": "Coach note",
            "K16": "185x5@8",
            "K17": "195x5@9"
        ],
        rows: 24,
        cols: 30
    )
    let section = locateWeekSections(in: grid)[0]

    let exercises = parseDay(in: grid, section: section, dayIndex: 0, endRow: grid.count)

    #expect(exercises[0].coachNote == "Coach note")
    #expect(exercises[0].sets[0].state == .logged)
    #expect(exercises[0].sets[0].setLog?.formatted == "185x5@8")
    #expect(exercises[0].sets[1].state == .logged)
    #expect(exercises[0].sets[1].setLog?.formatted == "195x5@9")
}

@Test func parsesSkipMarkerFromNotesContinuationRow() {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Hack SQ", "D15": "1", "F15": "7", "H15": "RPE 8", "K16": "skip"
        ],
        rows: 22,
        cols: 30
    )
    let section = locateWeekSections(in: grid)[0]

    let exercises = parseDay(in: grid, section: section, dayIndex: 0, endRow: grid.count)

    #expect(exercises[0].sets[0].state == .skipped)
    #expect(exercises[0].sets[0].setLog == nil)
}

@Test func ignoresAnchorNotesAsSetLogs() {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Standing Calve Raises", "D15": "1", "F15": "12", "H15": "RPE 9", "K15": "25x12, 12"
        ],
        rows: 20,
        cols: 30
    )
    let section = locateWeekSections(in: grid)[0]

    let exercises = parseDay(in: grid, section: section, dayIndex: 0, endRow: grid.count)

    #expect(exercises[0].coachNote == "25x12, 12")
    #expect(exercises[0].sets[0].state == .pending)
    #expect(exercises[0].sets[0].setLog == nil)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SheetParserLogTests`

Expected: FAIL because `ParsedSet` has no `state` or `setLog`.

- [ ] **Step 3: Extend `ParsedSet` and `parseDay`**

Replace `ParsedSet` and the `sets` construction in `WorkoutTracker/Parsing/SheetParser.swift` with:

```swift
struct ParsedSet {
    var index: Int
    var prescribedReps: String
    var prescribedLoad: String
    var percentOneRM: String?
    var state: SetState = .pending
    var setLog: SetLog? = nil
}

private func parsedLogState(from raw: String) -> (SetState, SetLog?) {
    let value = raw.trimmed
    if value.caseInsensitiveCompare("skip") == .orderedSame {
        return (.skipped, nil)
    }
    if let log = SetLog(formatted: value) {
        return (.logged, log)
    }
    return (.pending, nil)
}
```

Inside `parseDay`, compute each exercise's next anchor and read only continuation rows:

```swift
for (anchorIndex, r) in anchors.enumerated() {
    let rawName = grid.cell(row: r, col: cols.name).trimmed
    let (cadence, base) = splitCadence(rawName)
    let nextAnchor = anchorIndex + 1 < anchors.count ? anchors[anchorIndex + 1] : upper
    let setCount = max(Int(grid.cellOrEmpty(r, cols.sets).prefix { $0.isNumber }) ?? 1, 1)
    let reps = grid.cellOrEmpty(r, cols.reps)
    let load = grid.cellOrEmpty(r, cols.load)
    let pct = grid.cellOrEmpty(r, cols.percentOneRM)
    let note = grid.cellOrEmpty(r, cols.notes).trimmed
    let loadValues = splitLoadValues(load)
    let repsValues = reps.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    let sets = (0..<setCount).map { i in
        let logRow = r + i + 1
        let rawLog = logRow < nextAnchor ? grid.cellOrEmpty(logRow, cols.notes) : ""
        let (state, setLog) = parsedLogState(from: rawLog)
        return ParsedSet(
            index: i,
            prescribedReps: i < repsValues.count ? repsValues[i] : (repsValues.last ?? reps),
            prescribedLoad: i < loadValues.count ? loadValues[i] : (loadValues.last ?? load),
            percentOneRM: pct.isEmpty ? nil : pct,
            state: state,
            setLog: setLog
        )
    }
    result.append(
        ParsedExercise(
            name: rawName,
            baseName: base,
            cadence: cadence,
            coachNote: note.isEmpty ? nil : note,
            sets: sets
        )
    )
}
```

- [ ] **Step 4: Persist parsed Set state in `BlockBuilder`**

Update the `ExerciseSet` creation:

```swift
let set = ExerciseSet(
    index: $0.index,
    prescribedReps: $0.prescribedReps,
    prescribedLoad: $0.prescribedLoad,
    percentOneRM: $0.percentOneRM,
    state: $0.state
)
set.setLog = $0.setLog
return set
```

- [ ] **Step 5: Run focused and existing parser tests**

Run:

```bash
swift test --filter SheetParserLogTests
swift test --filter SheetParserTests
swift test --filter BlockBuilderTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add WorkoutTracker/Parsing/SheetParser.swift WorkoutTracker/Parsing/BlockBuilder.swift WorkoutTrackerTests/SheetParserLogTests.swift
git commit -m "feat: parse sheet set logs from continuation rows"
```

---

## Task 3: Add the `PendingWrite` Queue Model

**Files:**
- Create: `WorkoutTracker/Models/PendingWrite.swift`
- Modify: `WorkoutTracker/WorkoutTrackerApp.swift`
- Test: `WorkoutTrackerTests/PendingWriteTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import SwiftData
import Testing
@testable import WorkoutTracker

@MainActor
@Test func pendingWritePersistsSemanticTargetAndLock() throws {
    let container = try ModelContainer(
        for: Block.self, PendingWrite.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let ctx = container.mainContext
    let write = PendingWrite(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: "185x5@8",
        expectedCurrentValue: ""
    )
    ctx.insert(write)
    try ctx.save()

    let fetched = try #require(try ctx.fetch(FetchDescriptor<PendingWrite>()).first)
    #expect(fetched.blockTab == "Block 27")
    #expect(fetched.column == .notes)
    #expect(fetched.operation == .upsert)
    #expect(fetched.status == .pending)
    #expect(fetched.expectedCurrentValue == "")
}

@MainActor
@Test func pendingWriteConflictStatusRoundTrips() throws {
    let write = PendingWrite(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 0,
        column: .notes,
        operation: .delete,
        valueToWrite: nil,
        expectedCurrentValue: "185x5@8"
    )

    write.markConflict("Expected 185x5@8, found 190x5@9")

    #expect(write.status == .conflict)
    #expect(write.lastError == "Expected 185x5@8, found 190x5@9")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter PendingWriteTests`

Expected: FAIL because `PendingWrite` is undefined.

- [ ] **Step 3: Create `PendingWrite.swift`**

```swift
import Foundation
import SwiftData

enum PendingWriteColumn: String, Codable, Sendable {
    case notes
    case lastSetRPE
}

enum PendingWriteOperation: String, Codable, Sendable {
    case upsert
    case delete
}

enum PendingWriteStatus: String, Codable, Sendable {
    case pending
    case conflict
}

@Model
final class PendingWrite {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var blockTab: String
    var week: Int
    var day: Int
    var exerciseName: String
    var setIndex: Int
    var columnRaw: String
    var operationRaw: String
    var valueToWrite: String?
    var expectedCurrentValue: String
    var statusRaw: String
    var retryCount: Int
    var lastError: String?

    var column: PendingWriteColumn {
        get { PendingWriteColumn(rawValue: columnRaw) ?? .notes }
        set { columnRaw = newValue.rawValue }
    }

    var operation: PendingWriteOperation {
        get { PendingWriteOperation(rawValue: operationRaw) ?? .upsert }
        set { operationRaw = newValue.rawValue }
    }

    var status: PendingWriteStatus {
        get { PendingWriteStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        blockTab: String,
        week: Int,
        day: Int,
        exerciseName: String,
        setIndex: Int,
        column: PendingWriteColumn,
        operation: PendingWriteOperation,
        valueToWrite: String?,
        expectedCurrentValue: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.blockTab = blockTab
        self.week = week
        self.day = day
        self.exerciseName = exerciseName
        self.setIndex = setIndex
        self.columnRaw = column.rawValue
        self.operationRaw = operation.rawValue
        self.valueToWrite = valueToWrite
        self.expectedCurrentValue = expectedCurrentValue
        self.statusRaw = PendingWriteStatus.pending.rawValue
        self.retryCount = 0
        self.lastError = nil
    }

    func markConflict(_ message: String) {
        status = .conflict
        lastError = message
    }
}
```

- [ ] **Step 4: Include `PendingWrite` in the app container**

In `WorkoutTracker/WorkoutTrackerApp.swift`, change:

```swift
let container = try! ModelContainer(for: Block.self)
```

to:

```swift
let container = try! ModelContainer(for: Block.self, PendingWrite.self)
```

- [ ] **Step 5: Run the tests**

Run: `swift test --filter PendingWriteTests`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add WorkoutTracker/Models/PendingWrite.swift WorkoutTracker/WorkoutTrackerApp.swift WorkoutTrackerTests/PendingWriteTests.swift
git commit -m "feat: add pending write queue model"
```

---

## Task 4: Add A1 Helpers and Sheets Update Surface

**Files:**
- Modify: `WorkoutTracker/Parsing/SheetGrid.swift`
- Modify: `WorkoutTracker/Sheets/SheetsClient.swift`
- Modify: `WorkoutTracker/Sheets/GoogleSheetsClient.swift`
- Test: `WorkoutTrackerTests/SheetA1Tests.swift`

- [ ] **Step 1: Write the failing A1 tests**

```swift
import Testing
@testable import WorkoutTracker

@Test func rendersA1FromZeroBasedIndexes() {
    #expect(indexToA1(row: 0, col: 0) == "A1")
    #expect(indexToA1(row: 15, col: 10) == "K16")
    #expect(indexToA1(row: 0, col: 26) == "AA1")
}

@Test func rendersQuotedSingleCellRange() {
    #expect(singleCellRange(tabName: "Block 27", row: 15, col: 10) == "'Block 27'!K16")
    #expect(singleCellRange(tabName: "Kevin's Block", row: 0, col: 0) == "'Kevin''s Block'!A1")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SheetA1Tests`

Expected: FAIL because the A1 rendering helpers are undefined.

- [ ] **Step 3: Add helpers to `SheetGrid.swift`**

```swift
func columnName(_ zeroBasedColumn: Int) -> String {
    var value = zeroBasedColumn + 1
    var result = ""
    while value > 0 {
        let remainder = (value - 1) % 26
        result.insert(Character(UnicodeScalar(65 + remainder)!), at: result.startIndex)
        value = (value - 1) / 26
    }
    return result
}

func indexToA1(row: Int, col: Int) -> String {
    "\(columnName(col))\(row + 1)"
}

func quotedSheetName(_ name: String) -> String {
    "'\(name.replacingOccurrences(of: "'", with: "''"))'"
}

func singleCellRange(tabName: String, row: Int, col: Int) -> String {
    "\(quotedSheetName(tabName))!\(indexToA1(row: row, col: col))"
}
```

- [ ] **Step 4: Extend the Sheets client protocol**

In `WorkoutTracker/Sheets/SheetsClient.swift`, add:

```swift
func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws
```

The final protocol should be:

```swift
protocol SheetsClient: Sendable {
    func listTabTitles(spreadsheetId: String) async throws -> [String]
    func fetchTab(spreadsheetId: String, tabName: String) async throws -> SheetGrid
    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws
}
```

- [ ] **Step 5: Implement `GoogleSheetsClient.updateCells`**

Add this method to `GoogleSheetsClient`:

```swift
func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {
    let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values:batchUpdate")!
    struct ValueRange: Encodable {
        let range: String
        let majorDimension: String
        let values: [[String]]
    }
    struct Body: Encodable {
        let valueInputOption: String
        let data: [ValueRange]
    }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("Bearer \(try await tokenProvider())", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONEncoder().encode(
        Body(
            valueInputOption: "USER_ENTERED",
            data: [ValueRange(range: range, majorDimension: "ROWS", values: values)]
        )
    )

    let (_, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw SheetsError.malformedResponse }
    guard (200..<300).contains(http.statusCode) else { throw SheetsError.http(http.statusCode) }
}
```

- [ ] **Step 6: Update existing test stubs**

Every test `SheetsClient` stub must add:

```swift
func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}
```

- [ ] **Step 7: Run the tests**

Run:

```bash
swift test --filter SheetA1Tests
swift test --filter SyncCoordinatorTests
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add WorkoutTracker/Parsing/SheetGrid.swift WorkoutTracker/Sheets/SheetsClient.swift WorkoutTracker/Sheets/GoogleSheetsClient.swift WorkoutTrackerTests
git commit -m "feat: add sheets cell update surface"
```

---

## Task 5: Build `SheetWriter` With Dynamic Targeting and Verification

**Files:**
- Create: `WorkoutTracker/Sheets/SheetWriter.swift`
- Test: `WorkoutTrackerTests/SheetWriterTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import WorkoutTracker

private final class StubWriteClient: SheetsClient, @unchecked Sendable {
    var titles: [String] = ["Block 27"]
    var grid: SheetGrid
    var updates: [(range: String, values: [[String]])] = []

    init(grid: SheetGrid) {
        self.grid = grid
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] { titles }
    func fetchTab(spreadsheetId: String, tabName: String) async throws -> SheetGrid { grid }
    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {
        updates.append((range, values))
    }
}

private func writerFixture(_ cells: [String: String]) -> StubWriteClient {
    StubWriteClient(
        grid: gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes"
            ].merging(cells) { _, new in new },
            rows: 30,
            cols: 30
        )
    )
}

@Test func writesSetLogToNotesContinuationRow() async throws {
    let client = writerFixture(["C15": "Squat", "D15": "2"])
    let writer = SheetWriter(client: client)
    let request = SheetWriteRequest(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: "185x5@8",
        expectedCurrentValue: ""
    )

    try await writer.write(request, spreadsheetId: "sid")

    #expect(client.updates.count == 1)
    #expect(client.updates[0].range == "'Block 27'!K16")
    #expect(client.updates[0].values == [["185x5@8"]])
}

@Test func protectsAnchorNotesByWritingBelowAnchor() async throws {
    let client = writerFixture(["C15": "Squat", "D15": "1", "K15": "Coach note"])
    let writer = SheetWriter(client: client)
    let request = SheetWriteRequest(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: "185x5@8",
        expectedCurrentValue: ""
    )

    try await writer.write(request, spreadsheetId: "sid")

    #expect(client.updates[0].range == "'Block 27'!K16")
}

@Test func writesLastSetRPEToAnchorRow() async throws {
    let client = writerFixture(["C15": "Squat", "D15": "2"])
    let writer = SheetWriter(client: client)
    let request = SheetWriteRequest(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 1,
        column: .lastSetRPE,
        operation: .upsert,
        valueToWrite: "9",
        expectedCurrentValue: ""
    )

    try await writer.write(request, spreadsheetId: "sid")

    #expect(client.updates[0].range == "'Block 27'!I15")
    #expect(client.updates[0].values == [["9"]])
}

@Test func refusesUnexpectedCurrentCellValue() async throws {
    let client = writerFixture(["C15": "Squat", "D15": "1", "K16": "coach edited"])
    let writer = SheetWriter(client: client)
    let request = SheetWriteRequest(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: "185x5@8",
        expectedCurrentValue: ""
    )

    do {
        try await writer.write(request, spreadsheetId: "sid")
        Issue.record("Expected unexpected current value")
    } catch let error as SheetWriterError {
        #expect(error == .unexpectedCurrentValue(expected: "", actual: "coach edited"))
    } catch {
        Issue.record("Expected SheetWriterError, got \(error)")
    }
    #expect(client.updates.isEmpty)
}

@Test func refusesMissingContinuationRow() async throws {
    let client = writerFixture(["C15": "Squat", "D15": "1", "C16": "Bench"])
    let writer = SheetWriter(client: client)
    let request = SheetWriteRequest(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: "185x5@8",
        expectedCurrentValue: ""
    )

    do {
        try await writer.write(request, spreadsheetId: "sid")
        Issue.record("Expected missing set row")
    } catch let error as SheetWriterError {
        #expect(error == .setRowNotFound(exerciseName: "Squat", setIndex: 0))
    } catch {
        Issue.record("Expected SheetWriterError, got \(error)")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SheetWriterTests`

Expected: FAIL because `SheetWriter` and `SheetWriteRequest` are undefined.

- [ ] **Step 3: Create `SheetWriter.swift`**

```swift
import Foundation

struct SheetWriteRequest: Sendable, Equatable {
    var blockTab: String
    var week: Int
    var day: Int
    var exerciseName: String
    var setIndex: Int
    var column: PendingWriteColumn
    var operation: PendingWriteOperation
    var valueToWrite: String?
    var expectedCurrentValue: String

    @MainActor
    init(_ write: PendingWrite) {
        self.init(
            blockTab: write.blockTab,
            week: write.week,
            day: write.day,
            exerciseName: write.exerciseName,
            setIndex: write.setIndex,
            column: write.column,
            operation: write.operation,
            valueToWrite: write.valueToWrite,
            expectedCurrentValue: write.expectedCurrentValue
        )
    }

    init(
        blockTab: String,
        week: Int,
        day: Int,
        exerciseName: String,
        setIndex: Int,
        column: PendingWriteColumn,
        operation: PendingWriteOperation,
        valueToWrite: String?,
        expectedCurrentValue: String
    ) {
        self.blockTab = blockTab
        self.week = week
        self.day = day
        self.exerciseName = exerciseName
        self.setIndex = setIndex
        self.column = column
        self.operation = operation
        self.valueToWrite = valueToWrite
        self.expectedCurrentValue = expectedCurrentValue
    }
}

enum SheetWriterError: Error, Equatable, LocalizedError {
    case weekNotFound(Int)
    case dayNotFound(Int)
    case columnNotFound(String)
    case exerciseNotFound(String)
    case setRowNotFound(exerciseName: String, setIndex: Int)
    case unexpectedCurrentValue(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .weekNotFound(let week): return "Week \(week) was not found in the sheet"
        case .dayNotFound(let day): return "Day \(day) was not found in the sheet"
        case .columnNotFound(let column): return "\(column) column was not found"
        case .exerciseNotFound(let name): return "\(name) was not found in the sheet"
        case .setRowNotFound(let name, let index): return "Set \(index + 1) row was not found for \(name)"
        case .unexpectedCurrentValue(let expected, let actual):
            return "Expected '\(expected)', found '\(actual)'"
        }
    }
}

struct SheetWriter: Sendable {
    private let client: any SheetsClient

    init(client: any SheetsClient) {
        self.client = client
    }

    func write(_ request: SheetWriteRequest, spreadsheetId: String) async throws {
        let grid = try await client.fetchTab(spreadsheetId: spreadsheetId, tabName: request.blockTab)
        let target = try resolveTarget(for: request, in: grid)
        let actual = grid.cell(row: target.row, col: target.col).trimmed
        guard actual == request.expectedCurrentValue else {
            throw SheetWriterError.unexpectedCurrentValue(expected: request.expectedCurrentValue, actual: actual)
        }

        let range = singleCellRange(tabName: request.blockTab, row: target.row, col: target.col)
        let value = request.operation == .delete ? "" : (request.valueToWrite ?? "")
        try await client.updateCells(spreadsheetId: spreadsheetId, range: range, values: [[value]])
    }

    private func resolveTarget(for request: SheetWriteRequest, in grid: SheetGrid) throws -> (row: Int, col: Int) {
        let sections = locateWeekSections(in: grid)
        guard request.week > 0, request.week <= sections.count else {
            throw SheetWriterError.weekNotFound(request.week)
        }
        let section = sections[request.week - 1]
        guard request.day > 0, request.day <= section.dayStartCols.count else {
            throw SheetWriterError.dayNotFound(request.day)
        }
        let dayIndex = request.day - 1
        let cols = resolveDayColumns(in: grid, section: section, dayIndex: dayIndex)
        let col: Int
        switch request.column {
        case .notes:
            guard let notes = cols.notes else { throw SheetWriterError.columnNotFound("Notes") }
            col = notes
        case .lastSetRPE:
            guard let lastSetRPE = cols.lastSetRPE else { throw SheetWriterError.columnNotFound("Last set RPE") }
            col = lastSetRPE
        }

        let endRow = nextSectionStart(after: request.week - 1, sections: sections, grid: grid)
        let firstExerciseRow = section.roleHeaderRow + 1
        var anchorRows: [Int] = []
        for row in firstExerciseRow..<endRow {
            if !grid.cell(row: row, col: cols.name).trimmed.isEmpty {
                anchorRows.append(row)
            }
        }
        guard let anchorIndex = anchorRows.firstIndex(where: {
            grid.cell(row: $0, col: cols.name).trimmed == request.exerciseName
        }) else {
            throw SheetWriterError.exerciseNotFound(request.exerciseName)
        }

        let anchorRow = anchorRows[anchorIndex]
        if request.column == .lastSetRPE {
            return (anchorRow, col)
        }

        let nextAnchor = anchorIndex + 1 < anchorRows.count ? anchorRows[anchorIndex + 1] : endRow
        let setRow = anchorRow + request.setIndex + 1
        guard setRow < nextAnchor else {
            throw SheetWriterError.setRowNotFound(exerciseName: request.exerciseName, setIndex: request.setIndex)
        }
        return (setRow, col)
    }

    private func nextSectionStart(after index: Int, sections: [WeekSection], grid: SheetGrid) -> Int {
        index + 1 < sections.count ? sections[index + 1].headerRow : grid.count
    }
}
```

- [ ] **Step 4: Run writer tests**

Run: `swift test --filter SheetWriterTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WorkoutTracker/Sheets/SheetWriter.swift WorkoutTrackerTests/SheetWriterTests.swift
git commit -m "feat: add verified sheet writer"
```

---

## Task 6: Flush Pending Writes in `SyncCoordinator`

**Files:**
- Modify: `WorkoutTracker/Stores/SyncCoordinator.swift`
- Test: `WorkoutTrackerTests/SyncCoordinatorWriteTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import SwiftData
import Testing
@testable import WorkoutTracker

private final class FlushStubClient: SheetsClient, @unchecked Sendable {
    var grid: SheetGrid
    var updates: [(String, [[String]])] = []
    var shouldThrowOffline = false

    init(grid: SheetGrid) {
        self.grid = grid
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] { ["Block 27"] }
    func fetchTab(spreadsheetId: String, tabName: String) async throws -> SheetGrid {
        if shouldThrowOffline { throw URLError(.notConnectedToInternet) }
        return grid
    }
    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {
        updates.append((range, values))
    }
}

@MainActor
private func makeContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Block.self, PendingWrite.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

@MainActor
@Test func flushPendingWritesDeletesSuccessfulQueueItem() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    ctx.insert(PendingWrite(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: "185x5@8",
        expectedCurrentValue: ""
    ))
    try ctx.save()
    let client = FlushStubClient(grid: gridFromA1([
        "C12": "Day 1", "S12": "Day 2",
        "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
        "C15": "Squat", "D15": "1"
    ], rows: 24, cols: 30))
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    #expect(client.updates.map(\.0) == ["'Block 27'!K16"])
    #expect(try ctx.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    #expect(sync.state == .idle)
}

@MainActor
@Test func flushMarksConflictWhenVerificationFails() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    ctx.insert(PendingWrite(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: "185x5@8",
        expectedCurrentValue: ""
    ))
    try ctx.save()
    let client = FlushStubClient(grid: gridFromA1([
        "C12": "Day 1", "S12": "Day 2",
        "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
        "C15": "Squat", "D15": "1", "K16": "coach edited"
    ], rows: 24, cols: 30))
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.flushPending(spreadsheetId: "sid")

    let write = try #require(try ctx.fetch(FetchDescriptor<PendingWrite>()).first)
    #expect(write.status == .conflict)
    #expect(sync.state.isConflict)
}
```

Add this test helper in the same file:

```swift
private extension SyncCoordinator.State {
    var isConflict: Bool {
        if case .conflict = self { return true }
        return false
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SyncCoordinatorWriteTests`

Expected: FAIL because `flushPending(spreadsheetId:)` is undefined.

- [ ] **Step 3: Extend `SyncCoordinator.State`**

In `SyncCoordinator`, change `State` to:

```swift
enum State: Equatable {
    case idle
    case syncing
    case pendingWrites(Int)
    case offline
    case conflict([String])
}
```

- [ ] **Step 4: Add queue flushing**

Add this method to `SyncCoordinator`:

```swift
func flushPending(spreadsheetId: String) async {
    let descriptor = FetchDescriptor<PendingWrite>(
        predicate: #Predicate { $0.statusRaw == "pending" },
        sortBy: [SortDescriptor(\.createdAt)]
    )
    let pending = (try? context.fetch(descriptor)) ?? []
    guard !pending.isEmpty else {
        state = .idle
        return
    }

    state = .syncing
    let writer = SheetWriter(client: client)
    var conflicts: [String] = []

    for write in pending {
        do {
            try await writer.write(SheetWriteRequest(write), spreadsheetId: spreadsheetId)
            context.delete(write)
        } catch let error as SheetWriterError {
            let message = error.errorDescription ?? String(describing: error)
            write.markConflict(message)
            conflicts.append("\(write.exerciseName): \(message)")
        } catch {
            write.retryCount += 1
            write.lastError = String(describing: error)
            try? context.save()
            state = .pendingWrites(pending.count)
            return
        }
    }

    try? context.save()
    if conflicts.isEmpty {
        state = .idle
    } else {
        state = .conflict(conflicts)
    }
}
```

- [ ] **Step 5: Flush before every sync read**

At the start of `sync(spreadsheetId:)`, after `state = .syncing`, add:

```swift
await flushPending(spreadsheetId: spreadsheetId)
let stateAfterFlush = state
state = .syncing
```

Keep the existing read path after this line. When assigning the final state after parsing, preserve a conflict discovered during the write flush:

```swift
if case .conflict = stateAfterFlush {
    state = stateAfterFlush
} else {
    state = parsed.warnings.isEmpty ? .idle : .conflict(parsed.warnings)
}
```

- [ ] **Step 6: Run the tests**

Run:

```bash
swift test --filter SyncCoordinatorWriteTests
swift test --filter SyncCoordinatorTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add WorkoutTracker/Stores/SyncCoordinator.swift WorkoutTrackerTests/SyncCoordinatorWriteTests.swift WorkoutTrackerTests/SyncCoordinatorTests.swift
git commit -m "feat: flush verified pending writes"
```

---

## Task 7: Add Optimistic Logging Mutations to `WorkoutStore`

**Files:**
- Modify: `WorkoutTracker/Stores/WorkoutStore.swift`
- Test: `WorkoutTrackerTests/WorkoutStoreLoggingTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import SwiftData
import Testing
@testable import WorkoutTracker

@MainActor
private func loggingContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Block.self, PendingWrite.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

@MainActor
private func seededStore() throws -> (WorkoutStore, ModelContext, ExerciseSet) {
    let container = try loggingContainer()
    let ctx = container.mainContext
    let parsed = ParsedBlockModel(
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
                                    ParsedSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .pending, setLog: nil),
                                    ParsedSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE 9", percentOneRM: nil, state: .pending, setLog: nil)
                                ]
                            )
                        ]
                    )
                ]
            )
        ]
    )
    let block = BlockBuilder.makeBlock(from: parsed)
    ctx.insert(block)
    try ctx.save()
    let store = WorkoutStore(context: ctx)
    store.reload()
    let set = try #require(store.block?.weeks.first?.sessions.first?.exercises.first?.sets.sorted { $0.index < $1.index }.first)
    return (store, ctx, set)
}

@MainActor
@Test func logSetOptimisticallyUpdatesLocalSetAndQueuesWrite() throws {
    let (store, ctx, set) = try seededStore()
    let log = SetLog(weight: .pounds(185), reps: 5, rpe: 8)

    try store.log(set, as: log)

    #expect(set.state == .logged)
    #expect(set.setLog?.formatted == "185x5@8")
    let writes = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(writes.count == 1)
    #expect(writes[0].column == .notes)
    #expect(writes[0].valueToWrite == "185x5@8")
    #expect(writes[0].expectedCurrentValue == "")
}

@MainActor
@Test func loggingFinalSetQueuesLastSetRPEWrite() throws {
    let (store, ctx, firstSet) = try seededStore()
    let finalSet = try #require(firstSet.exercise?.sets.first { $0.index == 1 })

    try store.log(finalSet, as: SetLog(weight: .pounds(195), reps: 5, rpe: 9))

    let writes = try ctx.fetch(FetchDescriptor<PendingWrite>())
    #expect(writes.contains { $0.column == .lastSetRPE && $0.valueToWrite == "9" })
}

@MainActor
@Test func deleteSetClearsLocalSetAndQueuesDelete() throws {
    let (store, ctx, set) = try seededStore()
    try store.log(set, as: SetLog(weight: .pounds(185), reps: 5, rpe: 8))

    try store.deleteLog(for: set)

    #expect(set.state == .pending)
    #expect(set.setLog == nil)
    let delete = try #require(try ctx.fetch(FetchDescriptor<PendingWrite>()).last)
    #expect(delete.operation == .delete)
    #expect(delete.expectedCurrentValue == "185x5@8")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter WorkoutStoreLoggingTests`

Expected: FAIL because logging methods are undefined.

- [ ] **Step 3: Add logging errors and helpers**

Add to `WorkoutStore.swift`:

```swift
enum WorkoutLoggingError: Error, Equatable {
    case missingExercise
    case missingSession
    case missingWeek
    case missingBlock
}
```

Add these private helpers inside `WorkoutStore`:

```swift
private func targetParts(for set: ExerciseSet) throws -> (Block, Week, Session, Exercise) {
    guard let exercise = set.exercise else { throw WorkoutLoggingError.missingExercise }
    guard let session = exercise.session else { throw WorkoutLoggingError.missingSession }
    guard let week = session.week else { throw WorkoutLoggingError.missingWeek }
    guard let block = week.block else { throw WorkoutLoggingError.missingBlock }
    return (block, week, session, exercise)
}

private func enqueue(
    for set: ExerciseSet,
    column: PendingWriteColumn,
    operation: PendingWriteOperation,
    valueToWrite: String?,
    expectedCurrentValue: String
) throws {
    let (block, week, session, exercise) = try targetParts(for: set)
    context.insert(PendingWrite(
        blockTab: block.tabName,
        week: week.number,
        day: session.dayNumber,
        exerciseName: exercise.name,
        setIndex: set.index,
        column: column,
        operation: operation,
        valueToWrite: valueToWrite,
        expectedCurrentValue: expectedCurrentValue
    ))
}

private func isFinalSet(_ set: ExerciseSet) -> Bool {
    let sets = set.exercise?.sets ?? []
    return set.index == (sets.map(\.index).max() ?? set.index)
}

private func rpeLabel(_ rpe: Double) -> String {
    rpe.rounded() == rpe ? String(Int(rpe)) : String(rpe)
}
```

- [ ] **Step 4: Add public mutation methods**

Add to `WorkoutStore`:

```swift
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
```

- [ ] **Step 5: Run logging tests**

Run: `swift test --filter WorkoutStoreLoggingTests`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add WorkoutTracker/Stores/WorkoutStore.swift WorkoutTrackerTests/WorkoutStoreLoggingTests.swift
git commit -m "feat: add optimistic workout logging"
```

---

## Task 8: Overlay Pending Writes After Block Refresh

**Files:**
- Modify: `WorkoutTracker/Stores/SyncCoordinator.swift`
- Test: `WorkoutTrackerTests/SyncCoordinatorWriteTests.swift`

- [ ] **Step 1: Add a failing overlay test**

Append to `WorkoutTrackerTests/SyncCoordinatorWriteTests.swift`:

```swift
@MainActor
@Test func syncOverlaysStillPendingWritesOntoFreshBlock() async throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    ctx.insert(PendingWrite(
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: "Squat",
        setIndex: 0,
        column: .notes,
        operation: .upsert,
        valueToWrite: "185x5@8",
        expectedCurrentValue: ""
    ))
    try ctx.save()
    let client = FlushStubClient(grid: gridFromA1([
        "C12": "Day 1", "S12": "Day 2",
        "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
        "C15": "Squat", "D15": "1", "K16": "coach edited"
    ], rows: 24, cols: 30))
    let sync = SyncCoordinator(client: client, context: ctx)

    await sync.sync(spreadsheetId: "sid")

    let block = try #require(try ctx.fetch(FetchDescriptor<Block>()).first)
    let set = try #require(block.weeks.first?.sessions.first?.exercises.first?.sets.first)
    #expect(set.state == .logged)
    #expect(set.setLog?.formatted == "185x5@8")
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter syncOverlaysStillPendingWritesOntoFreshBlock`

Expected: FAIL because parsed fresh blocks do not overlay still-pending writes.

- [ ] **Step 3: Add overlay helpers in `SyncCoordinator`**

Add these private methods:

```swift
private func replacePersistedBlock(with block: Block) {
    overlayPendingWrites(on: block)
    for existing in (try? context.fetch(FetchDescriptor<Block>())) ?? [] { context.delete(existing) }
    context.insert(block)
    try? context.save()
}

private func overlayPendingWrites(on block: Block) {
    let writes = (try? context.fetch(FetchDescriptor<PendingWrite>())) ?? []
    for write in writes where write.blockTab == block.tabName && write.column == .notes {
        guard
            let set = findSet(
                in: block,
                week: write.week,
                day: write.day,
                exerciseName: write.exerciseName,
                setIndex: write.setIndex
            )
        else { continue }

        if write.operation == .delete {
            set.state = .pending
            set.setLog = nil
        } else if write.valueToWrite?.caseInsensitiveCompare("skip") == .orderedSame {
            set.state = .skipped
            set.setLog = nil
        } else if let value = write.valueToWrite, let log = SetLog(formatted: value) {
            set.state = .logged
            set.setLog = log
        }
    }
}

private func findSet(
    in block: Block,
    week: Int,
    day: Int,
    exerciseName: String,
    setIndex: Int
) -> ExerciseSet? {
    block.weeks.first { $0.number == week }?
        .sessions.first { $0.dayNumber == day }?
        .exercises.first { $0.name == exerciseName }?
        .sets.first { $0.index == setIndex }
}
```

Use the overlaying version of `replacePersistedBlock(with:)` and remove the previous duplicate method body.

- [ ] **Step 4: Run sync write tests**

Run: `swift test --filter SyncCoordinatorWriteTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WorkoutTracker/Stores/SyncCoordinator.swift WorkoutTrackerTests/SyncCoordinatorWriteTests.swift
git commit -m "feat: preserve pending logs across sync refresh"
```

---

## Task 9: Add Compact Logging Controls to Exercise Cards

**Files:**
- Create: `WorkoutTracker/Views/SetLogEditor.swift`
- Modify: `WorkoutTracker/Views/ExerciseCard.swift`
- Modify: `WorkoutTracker/Views/SessionView.swift`

- [ ] **Step 1: Create `SetLogEditor.swift`**

```swift
import SwiftUI

struct SetLogEditor: View {
    let set: ExerciseSet
    let onLog: (SetLog) -> Void
    let onSkip: () -> Void
    let onDelete: () -> Void

    @State private var weightText: String
    @State private var repsText: String
    @State private var rpeText: String

    init(
        set: ExerciseSet,
        onLog: @escaping (SetLog) -> Void,
        onSkip: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.set = set
        self.onLog = onLog
        self.onSkip = onSkip
        self.onDelete = onDelete
        let log = set.setLog
        _weightText = State(initialValue: log?.weight.label ?? (set.prescribedLoad == "BW" ? "BW" : ""))
        _repsText = State(initialValue: log.map { String($0.reps) } ?? "")
        _rpeText = State(initialValue: log.map { $0.rpe.rounded() == $0.rpe ? String(Int($0.rpe)) : String($0.rpe) } ?? "")
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("Wt", text: $weightText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
            TextField("Reps", text: $repsText)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
            TextField("RPE", text: $rpeText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)

            Button("Log") {
                guard let log = makeLog() else { return }
                onLog(log)
            }
            .buttonStyle(.glassProminent)
            .disabled(makeLog() == nil)

            Menu {
                Button("Skip", action: onSkip)
                if set.state != .pending {
                    Button("Clear", role: .destructive, action: onDelete)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
            }
            .buttonStyle(.glass)
        }
        .font(.callout)
    }

    private func makeLog() -> SetLog? {
        let weight: Weight
        if weightText.caseInsensitiveCompare("BW") == .orderedSame {
            weight = .bodyweight
        } else if let pounds = Double(weightText) {
            weight = .pounds(pounds)
        } else {
            return nil
        }
        guard let reps = Int(repsText), let rpe = Double(rpeText) else { return nil }
        return SetLog(weight: weight, reps: reps, rpe: rpe)
    }
}
```

- [ ] **Step 2: Update `ExerciseCard` to render controls below each chip**

Change the type signature and set loop:

```swift
struct ExerciseCard: View {
    let exercise: Exercise
    let onLog: (ExerciseSet, SetLog) -> Void
    let onSkip: (ExerciseSet) -> Void
    let onDelete: (ExerciseSet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(exercise.baseName)
                .font(.headline)

            if let note = exercise.coachNote {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(exercise.sets.sorted(by: { $0.index < $1.index }), id: \.persistentModelID) { set in
                    VStack(alignment: .leading, spacing: 8) {
                        SetChip(reps: set.prescribedReps, load: set.prescribedLoad)
                        if set.state == .logged, let log = set.setLog {
                            Text(log.formatted)
                                .font(.caption)
                                .foregroundStyle(Theme.accent)
                        } else if set.state == .skipped {
                            Text("skip")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        SetLogEditor(
                            set: set,
                            onLog: { onLog(set, $0) },
                            onSkip: { onSkip(set) },
                            onDelete: { onDelete(set) }
                        )
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
    }
}
```

- [ ] **Step 3: Wire store actions in `SessionView`**

Update the `ExerciseCard` call:

```swift
ExerciseCard(
    exercise: exercise,
    onLog: { set, log in
        try? workout.log(set, as: log)
        if let id = settings.spreadsheetId {
            Task { await sync.flushPending(spreadsheetId: id) }
        }
    },
    onSkip: { set in
        try? workout.skip(set)
        if let id = settings.spreadsheetId {
            Task { await sync.flushPending(spreadsheetId: id) }
        }
    },
    onDelete: { set in
        try? workout.deleteLog(for: set)
        if let id = settings.spreadsheetId {
            Task { await sync.flushPending(spreadsheetId: id) }
        }
    }
)
```

- [ ] **Step 4: Build the app**

Run:

```bash
xcodebuild -project WorkoutTracker.xcodeproj -scheme WorkoutTracker -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Expected: build succeeds. The new controls compile in the app target.

- [ ] **Step 5: Commit**

```bash
git add WorkoutTracker/Views/SetLogEditor.swift WorkoutTracker/Views/ExerciseCard.swift WorkoutTracker/Views/SessionView.swift
git commit -m "feat: add glass set logging controls"
```

---

## Task 10: Surface Sync Pending and Conflict State

**Files:**
- Create: `WorkoutTracker/Views/SyncStatusBanner.swift`
- Modify: `WorkoutTracker/Views/SessionView.swift`

- [ ] **Step 1: Create `SyncStatusBanner.swift`**

```swift
import SwiftUI

struct SyncStatusBanner: View {
    let state: SyncCoordinator.State

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .syncing:
            banner(text: "Syncing", symbol: "arrow.triangle.2.circlepath")
        case .pendingWrites(let count):
            banner(text: "\(count) unsynced", symbol: "icloud.slash")
        case .offline:
            banner(text: "Offline", symbol: "wifi.slash")
        case .conflict(let messages):
            banner(text: messages.first ?? "Sheet conflict", symbol: "exclamationmark.triangle")
        }
    }

    private func banner(text: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(text)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
        .padding(.horizontal)
    }
}
```

- [ ] **Step 2: Add the banner to `SessionView`**

Wrap the current session scroll content in a `VStack` and place the banner above the scroll:

```swift
if let session = workout.displayedSession {
    VStack(spacing: 0) {
        SyncStatusBanner(state: sync.state)
            .padding(.top, 8)
        ScrollView {
            GlassEffectContainer(spacing: Theme.cardSpacing) {
                LazyVStack(spacing: Theme.cardSpacing) {
                    ForEach(
                        session.exercises.sorted(by: { $0.order < $1.order }),
                        id: \.persistentModelID
                    ) { exercise in
                        ExerciseCard(
                            exercise: exercise,
                            onLog: { set, log in
                                try? workout.log(set, as: log)
                                if let id = settings.spreadsheetId {
                                    Task { await sync.flushPending(spreadsheetId: id) }
                                }
                            },
                            onSkip: { set in
                                try? workout.skip(set)
                                if let id = settings.spreadsheetId {
                                    Task { await sync.flushPending(spreadsheetId: id) }
                                }
                            },
                            onDelete: { set in
                                try? workout.deleteLog(for: set)
                                if let id = settings.spreadsheetId {
                                    Task { await sync.flushPending(spreadsheetId: id) }
                                }
                            }
                        )
                    }
                }
                .padding()
            }
        }
    }
}
```

- [ ] **Step 3: Build the app**

Run:

```bash
xcodebuild -project WorkoutTracker.xcodeproj -scheme WorkoutTracker -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Expected: build succeeds and `SyncStatusBanner` compiles in the app target.

- [ ] **Step 4: Commit**

```bash
git add WorkoutTracker/Views/SyncStatusBanner.swift WorkoutTracker/Views/SessionView.swift
git commit -m "feat: surface sync write status"
```

---

## Task 11: Final Verification

**Files:**
- No source edits unless a previous task exposed a compile or test failure.

- [ ] **Step 1: Run package tests**

Run:

```bash
swift test
```

Expected: all Swift Testing tests pass, including the existing parser and redesign tests.

- [ ] **Step 2: Build the iOS app target**

Run:

```bash
xcodebuild -project WorkoutTracker.xcodeproj -scheme WorkoutTracker -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Expected: build succeeds.

- [ ] **Step 3: Manual simulator smoke test**

Run the app from Xcode on iPhone 17 Pro. With a configured sheet:

1. Open the current Session.
2. Enter a weighted log on a Set with a blank continuation Notes cell.
3. Confirm the UI immediately shows the formatted value.
4. Pull to refresh.
5. Confirm the formatted value remains visible.
6. Edit the same Set and confirm the queue writes the edit only after matching the previous value.
7. Clear the Set and confirm it returns to Pending locally.
8. Choose Skip and confirm the local value displays `skip`.
9. If the raw Sheet has unexpected content in the target cell, confirm the UI shows a conflict banner and no overwrite happens.

- [ ] **Step 4: Commit any final test-only adjustments**

If the verification steps required a small test fixture correction, commit it:

```bash
git add WorkoutTracker WorkoutTrackerTests
git commit -m "test: verify logging write-back flow"
```

If no files changed during final verification, skip this commit.

---

## Self-Review

- **Spec coverage:** User stories 4, 12-19, 28-31, 37-38 are covered by SetLog parsing, local-first logging, pending queue persistence, verified Sheet writes, skip/delete/edit, sync flushing, and conflict states. User stories 6-11 are Plan 3. User stories 20-27 are Plan 4.
- **Placeholder scan:** The plan contains concrete file paths, test code, implementation code, commands, and expected outcomes for each task.
- **Type consistency:** `SetLog`, `ExerciseSet.setLog`, `PendingWrite`, `PendingWriteColumn`, `PendingWriteOperation`, `PendingWriteStatus`, `SheetWriteRequest`, `SheetWriter`, `SyncCoordinator.flushPending(spreadsheetId:)`, and `WorkoutStore.log/skip/deleteLog` are introduced before later tasks use them.
