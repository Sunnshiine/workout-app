# Read-Only Workout Viewer — Implementation Plan (Plan 1 of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sign in with Google, point the app at the training Sheet, fetch + parse the current Block, and display the current Session read-only.

**Architecture:** SwiftUI + `@Observable` stores over SwiftData (per the high-level design spec). Pure engines (Sheet Parser, Session Progress Tracker) have no I/O and are TDD'd against fixtures sampled from the real Block 27 tab. A `SheetsClient` protocol isolates all networking so the sync read-path is testable with a stub. No logging/write-back in this plan — that's Plan 2.

**Tech Stack:** Swift 6 / iOS 26, SwiftUI, SwiftData, Swift Testing (`import Testing`), GoogleSignIn-iOS (SPM), URLSession.

**Reference docs:** spec `docs/superpowers/specs/2026-05-24-high-level-app-design.md`; glossary `CONTEXT.md`; ADRs `docs/adr/0001..0003`; PRD issue #1.

---

## Naming decisions (read first)

- The domain term **Set** collides with Swift's `Set`. The SwiftData model is named **`ExerciseSet`** everywhere in code. All other domain names (`Block`, `Week`, `Session`, `Exercise`, `SetLog`) are used verbatim.
- Do **not** name the app target or any module `WorkoutKit` — that's an Apple framework. The app target is **`WorkoutTracker`**; models live in the app target (no separate framework in Plan 1).
- Sheet grids are `[[String]]` with **0-based** rows/columns, matching the Google Sheets API `values` shape (column A = index 0). Comments reference A1 notation (e.g. `C12`) for cross-checking against the real sheet.

## Real Block-27 structure (the parser's ground truth)

- Week sections begin at rows **12, 37, 60, 83** (1-based). Within a week section: **Day-header row** holds `Day 1..Day 4`; the **date** is one row below; the **role-header row** is **two rows below** the Day-header row.
- Day groups start at columns **C, S, AI, AX** (1-based) — these are *not* fixed and the name→Sets offset differs per day, so columns are always resolved by scanning, never hardcoded.
- Role-header strings (exact): `Sets`, `Reps`, `%1RM`, `Load`, `Last set RPE`, `Notes`. The **exercise name** is in the day group's first column (same column as the `Day N` header).
- Exercise rows: an **anchor row** has a non-empty name cell; the **continuation rows** beneath it (empty name cell) carry additional sets and the athlete's set logs (in the Notes column). Coach Notes sit in the Notes column on the anchor row.
- Tab names are inconsistent: `Block 1`, `Block 2`, `Block 3`, `Block - 4` … `Block - 26`, `Block 27`. Current block = highest trailing integer across tabs matching `^Block\s*-?\s*\d+$`.
- Training Max lives at `E7:E9` (Squat/Bench/Deadlift); may be blank (it is in this snapshot — fine, Plan 1 doesn't use it).
- **Known quirk:** weeks 3–4 have a stray duplicate `Sets` header (e.g. `T62`/`T85` in addition to the real `U`). `resolveDayColumns` takes the first match, which can mis-resolve the Sets column for those days. Low-risk in read-only Plan 1 (only affects displayed set *count*); Plan 2's verify-before-write is the real guard. Confirm against the live sheet during the Task 21 smoke test.

## File structure

```
WorkoutTracker/
  WorkoutTrackerApp.swift              # @main, ModelContainer, environment wiring
  Models/
    Block.swift                        # Block, Week, Session @Model
    Exercise.swift                     # Exercise, ExerciseSet @Model
    SetLog.swift                       # SetLog, SetState, Weight value types
  Parsing/
    SheetGrid.swift                    # [[String]] helpers: a1 lookup, day-group spans
    SheetParser.swift                  # raw grid -> Block (+ ParseWarning)
    BlockTabSelector.swift             # pick current block tab from titles
  Progress/
    SessionProgressTracker.swift       # currentSession / currentWeek derivation
  Sheets/
    SheetsClient.swift                 # protocol + DTOs + spreadsheetId(from:)
    GoogleSheetsClient.swift           # URLSession impl: listTabs, fetchTab
    GoogleAuth.swift                   # GoogleSignIn wrapper
  Stores/
    SettingsStore.swift                # @Observable: sheet URL, isConfigured, auth
    WorkoutStore.swift                 # @Observable: block, current/displayed session
    SyncCoordinator.swift              # @Observable: read-path state machine
  Views/
    RootView.swift                     # onboarding gate
    OnboardingView.swift               # sign-in + paste URL
    SessionView.swift                  # read-only session display
WorkoutTrackerTests/
  Support/SheetGridFixture.swift       # gridFromA1 helper + real Block-27 fixtures
  SheetParserTests.swift
  BlockTabSelectorTests.swift
  SessionProgressTrackerTests.swift
  SpreadsheetIdTests.swift
  PersistenceTests.swift
  SyncCoordinatorTests.swift
  WorkoutStoreTests.swift
```

---

## Task 1: Project scaffold + dependencies

**Files:** the Xcode project (created via Xcode), `WorkoutTracker/Info.plist`.

**External prerequisite (do once, by hand):** In Google Cloud Console create an OAuth 2.0 **iOS client ID** for this app's bundle id, enable the **Google Sheets API**, and note the client ID and its **reversed client ID** (used as the URL scheme). Without this, sign-in cannot work. This is a manual console step — no code substitutes for it.

- [ ] **Step 1: Create the app project**

In Xcode: File → New → Project → iOS App. Product name `WorkoutTracker`, Interface SwiftUI, Storage **SwiftData**, Language Swift. Set the project folder to the repo root so it lives beside `docs/`. Set the deployment target to **iOS 26.0** (Project → target → General → Minimum Deployments).

- [ ] **Step 2: Add GoogleSignIn via SPM**

File → Add Package Dependencies → `https://github.com/google/GoogleSignIn-iOS` → Up to Next Major `8.0.0`. Add the **GoogleSignIn** and **GoogleSignInSwift** products to the `WorkoutTracker` target.

- [ ] **Step 3: Configure the OAuth URL scheme**

In `WorkoutTracker/Info.plist`, add a URL type whose scheme is your **reversed client ID** (`com.googleusercontent.apps.XXXX`). Add key `GIDClientID` (String) with your client ID.

- [ ] **Step 4: Confirm the test target uses Swift Testing**

Ensure a `WorkoutTrackerTests` unit-test target exists. Create `WorkoutTrackerTests/Smoke.swift`:

```swift
import Testing
@testable import WorkoutTracker

@Test func harnessRuns() {
    #expect(Bool(true))
}
```

- [ ] **Step 5: Build & test**

Run: `xcodebuild -scheme WorkoutTracker -destination 'platform=iOS Simulator,name=iPhone 16' test`
Expected: build succeeds, `harnessRuns` passes.

- [ ] **Step 6: Commit**

```bash
git add WorkoutTracker WorkoutTracker.xcodeproj WorkoutTrackerTests
git commit -m "chore: scaffold WorkoutTracker app, SwiftData, GoogleSignIn, Swift Testing"
```

---

## Task 2: Domain value types — `SetState`, `Weight`, `SetLog`

**Files:** Create `WorkoutTracker/Models/SetLog.swift`; Test `WorkoutTrackerTests/SetLogTests.swift`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import WorkoutTracker

@Test func setLogFormatsWeightedAndBodyweight() {
    let weighted = SetLog(weight: .pounds(185), reps: 7, rpe: 6)
    #expect(weighted.formatted == "185x7@6")

    let bw = SetLog(weight: .bodyweight, reps: 12, rpe: 7)
    #expect(bw.formatted == "BWx12@7")
}

@Test func weightDropsTrailingZero() {
    #expect(Weight.pounds(182.5).label == "182.5")
    #expect(Weight.pounds(185).label == "185")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme WorkoutTracker -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:WorkoutTrackerTests/SetLogTests`
Expected: FAIL — `Weight`/`SetLog` undefined.

- [ ] **Step 3: Implement**

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

    var formatted: String {
        let rpeLabel = rpe.rounded() == rpe ? String(Int(rpe)) : String(rpe)
        return "\(weight.label)x\(reps)@\(rpeLabel)"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WorkoutTracker/Models/SetLog.swift WorkoutTrackerTests/SetLogTests.swift
git commit -m "feat: add SetState, Weight, SetLog value types"
```

---

## Task 3: SwiftData models — `Block`/`Week`/`Session`/`Exercise`/`ExerciseSet`

**Files:** Create `WorkoutTracker/Models/Block.swift`, `WorkoutTracker/Models/Exercise.swift`; Test `WorkoutTrackerTests/PersistenceTests.swift`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import SwiftData
@testable import WorkoutTracker

@MainActor
@Test func blockRoundTripsThroughSwiftData() throws {
    let container = try ModelContainer(
        for: Block.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let ctx = container.mainContext

    let set = ExerciseSet(index: 0, prescribedReps: "12", prescribedLoad: "RPE8", percentOneRM: nil, state: .pending)
    let ex = Exercise(name: "0:3:0 Standing Calve Raises", baseName: "Standing Calve Raises", cadence: "0:3:0", coachNote: nil)
    ex.sets = [set]
    let session = Session(dayNumber: 1, date: nil)
    session.exercises = [ex]
    let week = Week(number: 1)
    week.sessions = [session]
    let block = Block(tabName: "Block 27", squatTM: nil, benchTM: nil, deadliftTM: nil)
    block.weeks = [week]
    ctx.insert(block)
    try ctx.save()

    let fetched = try ctx.fetch(FetchDescriptor<Block>())
    #expect(fetched.count == 1)
    #expect(fetched[0].weeks.first?.sessions.first?.exercises.first?.sets.first?.prescribedReps == "12")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme WorkoutTracker -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:WorkoutTrackerTests/PersistenceTests`
Expected: FAIL — models undefined.

- [ ] **Step 3: Implement `Block.swift`**

```swift
import Foundation
import SwiftData

@Model
final class Block {
    @Attribute(.unique) var tabName: String
    var squatTM: Double?
    var benchTM: Double?
    var deadliftTM: Double?
    @Relationship(deleteRule: .cascade, inverse: \Week.block) var weeks: [Week] = []

    init(tabName: String, squatTM: Double?, benchTM: Double?, deadliftTM: Double?) {
        self.tabName = tabName
        self.squatTM = squatTM
        self.benchTM = benchTM
        self.deadliftTM = deadliftTM
    }
}

@Model
final class Week {
    var number: Int
    var block: Block?
    @Relationship(deleteRule: .cascade, inverse: \Session.week) var sessions: [Session] = []

    init(number: Int) { self.number = number }
}

@Model
final class Session {
    var dayNumber: Int
    var date: Date?
    var week: Week?
    @Relationship(deleteRule: .cascade, inverse: \Exercise.session) var exercises: [Exercise] = []

    init(dayNumber: Int, date: Date?) {
        self.dayNumber = dayNumber
        self.date = date
    }
}
```

- [ ] **Step 4: Implement `Exercise.swift`**

```swift
import Foundation
import SwiftData

@Model
final class Exercise {
    var name: String          // full, includes cadence
    var baseName: String      // cadence stripped
    var cadence: String?
    var coachNote: String?
    var order: Int            // position within the session (preserves sheet order)
    var session: Session?
    @Relationship(deleteRule: .cascade, inverse: \ExerciseSet.exercise) var sets: [ExerciseSet] = []

    init(name: String, baseName: String, cadence: String?, coachNote: String?, order: Int = 0) {
        self.name = name
        self.baseName = baseName
        self.cadence = cadence
        self.coachNote = coachNote
        self.order = order
    }
}

@Model
final class ExerciseSet {
    var index: Int
    var prescribedReps: String     // "12", "11 - 12", "AMRAP"
    var prescribedLoad: String     // "RPE8", "Drop 10%", "BW", ...
    var percentOneRM: String?
    var stateRaw: String
    var setLogData: Data?          // encoded SetLog (Plan 2 writes this)
    var exercise: Exercise?

    var state: SetState {
        get { SetState(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
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

- [ ] **Step 5: Run test to verify it passes**

Run the Step 2 command. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add WorkoutTracker/Models/Block.swift WorkoutTracker/Models/Exercise.swift WorkoutTrackerTests/PersistenceTests.swift
git commit -m "feat: add SwiftData models for Block hierarchy"
```

---

## Task 4: Spreadsheet ID extraction from a Sheet URL

**Files:** Create `WorkoutTracker/Sheets/SheetsClient.swift` (start the file); Test `WorkoutTrackerTests/SpreadsheetIdTests.swift`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import WorkoutTracker

@Test func extractsSpreadsheetId() {
    let url = "https://docs.google.com/spreadsheets/d/1AbC_dEF123/edit#gid=0"
    #expect(extractSpreadsheetId(from: url) == "1AbC_dEF123")
}

@Test func returnsNilForNonSheetUrl() {
    #expect(extractSpreadsheetId(from: "https://example.com/foo") == nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild ... test -only-testing:WorkoutTrackerTests/SpreadsheetIdTests` (same destination as before).
Expected: FAIL — `spreadsheetId(from:)` undefined.

- [ ] **Step 3: Implement (in `SheetsClient.swift`)**

```swift
import Foundation

/// Extracts the spreadsheet id from a standard Google Sheets URL:
/// https://docs.google.com/spreadsheets/d/<ID>/edit...
func extractSpreadsheetId(from url: String) -> String? {
    guard let range = url.range(of: "/spreadsheets/d/") else { return nil }
    let rest = url[range.upperBound...]
    let id = rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
    return id.isEmpty ? nil : String(id)
}
```

- [ ] **Step 4: Run test to verify it passes** — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WorkoutTracker/Sheets/SheetsClient.swift WorkoutTrackerTests/SpreadsheetIdTests.swift
git commit -m "feat: extract spreadsheet id from Sheet URL"
```

---

## Task 5: Block tab selection from inconsistent titles

**Files:** Create `WorkoutTracker/Parsing/BlockTabSelector.swift`; Test `WorkoutTrackerTests/BlockTabSelectorTests.swift`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import WorkoutTracker

@Test func picksHighestNumberedBlockTab() {
    let titles = ["Intro", "Block 1", "Block - 26", "Block 27", "Sub workout", "RPE Chart"]
    #expect(currentBlockTab(from: titles) == "Block 27")
}

@Test func handlesDashAndNoDashNaming() {
    #expect(currentBlockTab(from: ["Block 3", "Block - 4", "Block - 28"]) == "Block - 28")
}

@Test func returnsNilWhenNoBlockTabs() {
    #expect(currentBlockTab(from: ["Intro", "Mobility Drills"]) == nil)
}
```

- [ ] **Step 2: Run test to verify it fails** — Expected: FAIL — `currentBlockTab` undefined.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Returns the title of the highest-numbered block tab, tolerating both
/// "Block N" and "Block - N" naming. Non-block tabs are ignored.
func currentBlockTab(from titles: [String]) -> String? {
    let regex = /^Block\s*-?\s*(\d+)$/
    var best: (number: Int, title: String)?
    for title in titles {
        guard let m = title.wholeMatch(of: regex), let n = Int(m.1) else { continue }
        if best == nil || n > best!.number { best = (n, title) }
    }
    return best?.title
}
```

- [ ] **Step 4: Run test to verify it passes** — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WorkoutTracker/Parsing/BlockTabSelector.swift WorkoutTrackerTests/BlockTabSelectorTests.swift
git commit -m "feat: select current block tab from inconsistent titles"
```

---

## Task 6: Sheet grid helpers + test fixture

**Files:** Create `WorkoutTracker/Parsing/SheetGrid.swift`; Create `WorkoutTrackerTests/Support/SheetGridFixture.swift`.

- [ ] **Step 1: Write the failing test** (`WorkoutTrackerTests/SheetGridTests.swift`)

```swift
import Testing
@testable import WorkoutTracker

@Test func a1HelperPlacesValues() {
    let grid = gridFromA1(["C12": "Day 1", "S12": "Day 2"], rows: 13, cols: 20)
    #expect(grid.cell(row: 11, col: 2) == "Day 1")   // C12 -> r11,c2 (0-based)
    #expect(grid.cell(row: 11, col: 18) == "Day 2")  // S12 -> r11,c18
    #expect(grid.cell(row: 0, col: 0) == "")          // empty default
    #expect(grid.cell(row: 99, col: 99) == "")        // out of bounds -> ""
}
```

- [ ] **Step 2: Run test to verify it fails** — Expected: FAIL.

- [ ] **Step 3: Implement grid helpers (`SheetGrid.swift`)**

```swift
import Foundation

typealias SheetGrid = [[String]]

extension Array where Element == [String] {
    /// Safe accessor: returns "" for out-of-bounds (Sheets API returns ragged rows).
    func cell(row: Int, col: Int) -> String {
        guard row >= 0, row < count, col >= 0, col < self[row].count else { return "" }
        return self[row][col]
    }
}

/// Converts an A1 reference like "AI12" to 0-based (row, col).
func a1ToIndex(_ a1: String) -> (row: Int, col: Int) {
    var col = 0
    var idx = a1.startIndex
    while idx < a1.endIndex, a1[idx].isLetter {
        col = col * 26 + (Int(a1[idx].asciiValue! - 64))  // A=1
        idx = a1.index(after: idx)
    }
    let row = Int(a1[idx...]) ?? 1
    return (row - 1, col - 1)
}
```

- [ ] **Step 4: Implement the fixture helper (`Support/SheetGridFixture.swift`)**

```swift
@testable import WorkoutTracker

/// Builds a 0-based grid from A1-keyed cells (rows/cols are 1-based A1).
func gridFromA1(_ cells: [String: String], rows: Int, cols: Int) -> SheetGrid {
    var g = SheetGrid(repeating: [String](repeating: "", count: cols), count: rows)
    for (a1, value) in cells {
        let (r, c) = a1ToIndex(a1)
        if r < rows, c < cols { g[r][c] = value }
    }
    return g
}
```

- [ ] **Step 5: Run test to verify it passes** — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add WorkoutTracker/Parsing/SheetGrid.swift WorkoutTrackerTests/Support/SheetGridFixture.swift WorkoutTrackerTests/SheetGridTests.swift
git commit -m "feat: add sheet grid accessor + A1 fixture helper"
```

---

## Task 7: Parser — locate week sections and day groups

**Files:** Create `WorkoutTracker/Parsing/SheetParser.swift`; Test `WorkoutTrackerTests/SheetParserTests.swift`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import WorkoutTracker

@Test func locatesFourDayGroupsPerWeekSection() {
    // Real Block-27 week-1 day headers (1-based A1): C12,S12,AI12,AX12
    let grid = gridFromA1([
        "C12": "Day 1", "S12": "Day 2", "AI12": "Day 3", "AX12": "Day 4",
        "C37": "Day 1", "S37": "Day 2", "AI37": "Day 3", "AX37": "Day 4",
    ], rows: 40, cols: 60)

    let sections = locateWeekSections(in: grid)
    #expect(sections.count == 2)
    #expect(sections[0].headerRow == 11)            // row 12 (0-based 11)
    #expect(sections[0].dayStartCols == [2, 18, 34, 49]) // C,S,AI,AX (0-based)
    #expect(sections[0].roleHeaderRow == 13)        // header + 2
}
```

- [ ] **Step 2: Run test to verify it fails** — Expected: FAIL — `locateWeekSections` undefined.

- [ ] **Step 3: Implement (start `SheetParser.swift`)**

```swift
import Foundation

struct WeekSection {
    let headerRow: Int       // 0-based row holding "Day N"
    let roleHeaderRow: Int   // headerRow + 2
    let dateRow: Int         // headerRow + 1
    let dayStartCols: [Int]  // 0-based columns of Day 1..Day 4
}

private let dayHeaderPattern = /^Day [1-4]$/

/// Finds each week section by scanning for rows that contain "Day 1".."Day 4".
func locateWeekSections(in grid: SheetGrid) -> [WeekSection] {
    var byRow: [Int: [Int]] = [:]   // row -> day start columns (ascending)
    for r in 0..<grid.count {
        for c in 0..<grid[r].count where grid[r][c].wholeMatch(of: dayHeaderPattern) != nil {
            byRow[r, default: []].append(c)
        }
    }
    return byRow.keys.sorted().compactMap { row in
        let cols = byRow[row]!.sorted()
        guard !cols.isEmpty else { return nil }
        return WeekSection(headerRow: row, roleHeaderRow: row + 2, dateRow: row + 1, dayStartCols: cols)
    }
}
```

- [ ] **Step 4: Run test to verify it passes** — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WorkoutTracker/Parsing/SheetParser.swift WorkoutTrackerTests/SheetParserTests.swift
git commit -m "feat: parser locates week sections and day groups"
```

---

## Task 8: Parser — resolve role columns within a day group

**Files:** Modify `WorkoutTracker/Parsing/SheetParser.swift`; Modify `WorkoutTrackerTests/SheetParserTests.swift`.

- [ ] **Step 1: Write the failing test**

```swift
@Test func resolvesRoleColumnsByHeaderScan() {
    // Day-1 role header row (real): D14 Sets, F14 Reps, G14 %1RM, H14 Load,
    // I14 Last set RPE, K14 Notes. Name column = day start (C).
    let grid = gridFromA1([
        "C12": "Day 1", "S12": "Day 2",
        "D14": "Sets", "F14": "Reps", "G14": "%1RM", "H14": "Load",
        "I14": "Last set RPE", "K14": "Notes",
    ], rows: 20, cols: 30)
    let section = locateWeekSections(in: grid)[0]

    let cols = resolveDayColumns(in: grid, section: section, dayIndex: 0)
    #expect(cols.name == 2)        // C
    #expect(cols.sets == 3)        // D
    #expect(cols.reps == 5)        // F
    #expect(cols.percentOneRM == 6) // G
    #expect(cols.load == 7)        // H
    #expect(cols.lastSetRPE == 8)  // I
    #expect(cols.notes == 10)      // K
}
```

- [ ] **Step 2: Run test to verify it fails** — Expected: FAIL.

- [ ] **Step 3: Implement (append to `SheetParser.swift`)**

```swift
struct DayColumns {
    let name: Int
    let sets: Int?
    let reps: Int?
    let percentOneRM: Int?
    let load: Int?
    let lastSetRPE: Int?
    let notes: Int?
    let span: Range<Int>   // [dayStart, nextDayStart)
}

/// Resolves role columns by scanning the role-header row within the day's span.
/// Columns are never hardcoded (ADR 0003).
func resolveDayColumns(in grid: SheetGrid, section: WeekSection, dayIndex: Int) -> DayColumns {
    let starts = section.dayStartCols
    let start = starts[dayIndex]
    let end = dayIndex + 1 < starts.count
        ? starts[dayIndex + 1]
        : start + (starts.count > 1 ? starts[1] - starts[0] : 16)
    let span = start..<end

    func find(_ label: String) -> Int? {
        (span.lowerBound..<span.upperBound).first {
            grid.cell(row: section.roleHeaderRow, col: $0).caseInsensitiveCompare(label) == .orderedSame
        }
    }
    return DayColumns(
        name: start,
        sets: find("Sets"),
        reps: find("Reps"),
        percentOneRM: find("%1RM"),
        load: find("Load"),
        lastSetRPE: find("Last set RPE"),
        notes: find("Notes"),
        span: span)
}
```

- [ ] **Step 4: Run test to verify it passes** — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WorkoutTracker/Parsing/SheetParser.swift WorkoutTrackerTests/SheetParserTests.swift
git commit -m "feat: parser resolves role columns by header scan"
```

---

## Task 9: Parser — cadence split

**Files:** Modify `WorkoutTracker/Parsing/SheetParser.swift`; Modify `WorkoutTrackerTests/SheetParserTests.swift`.

- [ ] **Step 1: Write the failing test**

```swift
@Test func splitsCadencePrefix() {
    #expect(splitCadence("2-3:1:0 BB RDL").cadence == "2-3:1:0")
    #expect(splitCadence("2-3:1:0 BB RDL").base == "BB RDL")
    #expect(splitCadence("0:3:0 Standing Calve Raises").base == "Standing Calve Raises")
    #expect(splitCadence("Lateral Raises").cadence == nil)
    #expect(splitCadence("Lateral Raises").base == "Lateral Raises")
}
```

- [ ] **Step 2: Run test to verify it fails** — Expected: FAIL.

- [ ] **Step 3: Implement (append to `SheetParser.swift`)**

```swift
/// Splits a leading tempo prefix (e.g. "2-3:1-2:0") from the base exercise name.
func splitCadence(_ name: String) -> (cadence: String?, base: String) {
    let pattern = /^(\d+(?:-\d+)?:\d+(?:-\d+)?:\d+(?:-\d+)?)\s+(.+)$/
    if let m = name.wholeMatch(of: pattern) {
        return (String(m.1), String(m.2))
    }
    return (nil, name)
}
```

- [ ] **Step 4: Run test to verify it passes** — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WorkoutTracker/Parsing/SheetParser.swift WorkoutTrackerTests/SheetParserTests.swift
git commit -m "feat: parser splits cadence prefix from exercise name"
```

---

## Task 10: Parser — parse the exercises in one day group

**Files:** Modify `WorkoutTracker/Parsing/SheetParser.swift`; Modify `WorkoutTrackerTests/SheetParserTests.swift`.

This produces lightweight value structs (not SwiftData models) so the parser stays pure and testable. Models are built from these in Task 12.

- [ ] **Step 1: Write the failing test** (uses real Week-1/Day-1 rows)

```swift
@Test func parsesAnchorAndContinuationRows() {
    // Real rows: C15 anchor "0:3:0 Standing Calve Raises", D15 Sets=2, F15 Reps=12,
    // H15 Load "RPE9, RPE10", K15 coach/log "25x12, 12". Next anchor C22.
    let grid = gridFromA1([
        "C12": "Day 1", "S12": "Day 2",
        "D14": "Sets", "F14": "Reps", "G14": "%1RM", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
        "C15": "0:3:0 Standing Calve Raises", "D15": "2", "F15": "12", "H15": "RPE9, RPE10", "K15": "Superset cue",
        "C22": "0:2:0 Pull Up", "D22": "2", "F22": "AMRAP", "H22": "BW",
    ], rows: 30, cols: 30)
    let section = locateWeekSections(in: grid)[0]

    let exercises = parseDay(in: grid, section: section, dayIndex: 0, endRow: grid.count)
    #expect(exercises.count == 2)
    #expect(exercises[0].name == "0:3:0 Standing Calve Raises")
    #expect(exercises[0].baseName == "Standing Calve Raises")
    #expect(exercises[0].coachNote == "Superset cue")
    #expect(exercises[0].sets.count == 2)           // "2" sets
    #expect(exercises[0].sets[0].prescribedReps == "12")
    #expect(exercises[0].sets[0].prescribedLoad == "RPE9, RPE10")
    #expect(exercises[1].baseName == "Pull Up")
    #expect(exercises[1].sets[0].prescribedReps == "AMRAP")
    #expect(exercises[1].sets[0].prescribedLoad == "BW")
}
```

- [ ] **Step 2: Run test to verify it fails** — Expected: FAIL.

- [ ] **Step 3: Implement (append to `SheetParser.swift`)**

```swift
struct ParsedSet {
    var index: Int
    var prescribedReps: String
    var prescribedLoad: String
    var percentOneRM: String?
}

struct ParsedExercise {
    var name: String
    var baseName: String
    var cadence: String?
    var coachNote: String?
    var sets: [ParsedSet]
}

/// Parses all exercises in one day group. Anchor rows have a non-empty name cell;
/// the row count for an exercise is `max(Sets value, 1)` (continuation rows hold
/// extra sets / set logs; logs are read in Plan 2).
func parseDay(in grid: SheetGrid, section: WeekSection, dayIndex: Int, endRow: Int) -> [ParsedExercise] {
    let cols = resolveDayColumns(in: grid, section: section, dayIndex: dayIndex)
    let firstRow = section.roleHeaderRow + 1
    let upper = min(endRow, grid.count)

    // Collect anchor rows (name cell non-empty), stopping at the next week's day header.
    var anchors: [Int] = []
    if firstRow < upper {
        for r in firstRow..<upper {
            if grid.cell(row: r, col: cols.name).wholeMatch(of: dayHeaderPattern) != nil { break }
            if !grid.cell(row: r, col: cols.name).trimmed.isEmpty { anchors.append(r) }
        }
    }

    var result: [ParsedExercise] = []
    for r in anchors {
        let rawName = grid.cell(row: r, col: cols.name).trimmed
        let (cadence, base) = splitCadence(rawName)
        // Sets cell may be "2" or a range like "3 - 4"; take the leading integer.
        let setCount = max(Int(grid.cellOrEmpty(r, cols.sets).prefix { $0.isNumber }) ?? 1, 1)
        let reps = grid.cellOrEmpty(r, cols.reps)
        let load = grid.cellOrEmpty(r, cols.load)
        let pct = grid.cellOrEmpty(r, cols.percentOneRM)
        let note = grid.cellOrEmpty(r, cols.notes).trimmed
        let sets = (0..<setCount).map {
            ParsedSet(index: $0, prescribedReps: reps, prescribedLoad: load,
                      percentOneRM: pct.isEmpty ? nil : pct)
        }
        result.append(ParsedExercise(
            name: rawName, baseName: base, cadence: cadence,
            coachNote: note.isEmpty ? nil : note, sets: sets))
    }
    return result
}

extension String { var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } }
extension Array where Element == [String] {
    func cellOrEmpty(_ row: Int, _ col: Int?) -> String { col.map { cell(row: row, col: $0) } ?? "" }
}
```

- [ ] **Step 4: Run test to verify it passes** — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WorkoutTracker/Parsing/SheetParser.swift WorkoutTrackerTests/SheetParserTests.swift
git commit -m "feat: parser parses exercises within a day group"
```

---

## Task 11: Parser — assemble the full Block (+ warnings)

**Files:** Modify `WorkoutTracker/Parsing/SheetParser.swift`; Modify `WorkoutTrackerTests/SheetParserTests.swift`.

- [ ] **Step 1: Write the failing test**

```swift
@Test func assemblesBlockFromTwoWeekSections() {
    let grid = gridFromA1([
        "C12": "Day 1", "S12": "Day 2", "AI12": "Day 3", "AX12": "Day 4",
        "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
        "C15": "0:3:0 Standing Calve Raises", "D15": "2", "F15": "12", "H15": "RPE9, RPE10",
        "C37": "Day 1", "S37": "Day 2", "AI37": "Day 3", "AX37": "Day 4",
        "D39": "Sets", "F39": "Reps", "H39": "Load", "K39": "Notes",
        "C40": "0:3:0 Standing Calve Raises", "D40": "2", "F40": "11 - 12", "H40": "RPE9, RPE10",
    ], rows: 45, cols: 60)

    let parsed = SheetParser().parse(grid: grid, tabName: "Block 27")
    #expect(parsed.warnings.isEmpty)
    #expect(parsed.block.weeks.count == 2)
    #expect(parsed.block.weeks[0].number == 1)
    #expect(parsed.block.weeks[0].days.count == 4)
    #expect(parsed.block.weeks[0].days[0].exercises[0].baseName == "Standing Calve Raises")
    #expect(parsed.block.weeks[1].days[0].exercises[0].sets[0].prescribedReps == "11 - 12")
}

@Test func warnsWhenNoWeekSections() {
    let parsed = SheetParser().parse(grid: gridFromA1([:], rows: 5, cols: 5), tabName: "Block 27")
    #expect(parsed.warnings.contains { $0.contains("no week sections") })
}
```

- [ ] **Step 2: Run test to verify it fails** — Expected: FAIL — `SheetParser`/`ParsedBlock` undefined.

- [ ] **Step 3: Implement (append to `SheetParser.swift`)**

```swift
import Foundation

struct ParsedSession { var dayNumber: Int; var date: Date?; var exercises: [ParsedExercise] }
struct ParsedWeek { var number: Int; var days: [ParsedSession] }
struct ParsedBlockModel { var tabName: String; var weeks: [ParsedWeek] }
struct ParsedBlock { var block: ParsedBlockModel; var warnings: [String] }

struct SheetParser {
    func parse(grid: SheetGrid, tabName: String) -> ParsedBlock {
        var warnings: [String] = []
        let sections = locateWeekSections(in: grid)
        if sections.isEmpty {
            warnings.append("Parse warning: no week sections (no 'Day N' headers) in \(tabName)")
            return ParsedBlock(block: ParsedBlockModel(tabName: tabName, weeks: []), warnings: warnings)
        }
        var weeks: [ParsedWeek] = []
        for (i, section) in sections.enumerated() {
            let endRow = (i + 1 < sections.count) ? sections[i + 1].headerRow : grid.count
            var days: [ParsedSession] = []
            for dayIndex in 0..<section.dayStartCols.count {
                let date = parseDate(grid.cell(row: section.dateRow, col: section.dayStartCols[dayIndex]))
                let exercises = parseDay(in: grid, section: section, dayIndex: dayIndex, endRow: endRow)
                days.append(ParsedSession(dayNumber: dayIndex + 1, date: date, exercises: exercises))
            }
            weeks.append(ParsedWeek(number: i + 1, days: days))
        }
        return ParsedBlock(block: ParsedBlockModel(tabName: tabName, weeks: weeks), warnings: warnings)
    }

    private func parseDate(_ s: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "M/d/yyyy"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s.trimmed)
    }
}
```

- [ ] **Step 4: Run test to verify it passes** — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WorkoutTracker/Parsing/SheetParser.swift WorkoutTrackerTests/SheetParserTests.swift
git commit -m "feat: parser assembles full Block with warnings"
```

---

## Task 12: Map parsed values into SwiftData models

**Files:** Create `WorkoutTracker/Parsing/BlockBuilder.swift`; Test `WorkoutTrackerTests/BlockBuilderTests.swift`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import SwiftData
@testable import WorkoutTracker

@MainActor
@Test func buildsModelGraphFromParsedBlock() throws {
    let parsed = ParsedBlockModel(tabName: "Block 27", weeks: [
        ParsedWeek(number: 1, days: [
            ParsedSession(dayNumber: 1, date: nil, exercises: [
                ParsedExercise(name: "0:3:0 Calf", baseName: "Calf", cadence: "0:3:0",
                               coachNote: nil, sets: [ParsedSet(index: 0, prescribedReps: "12",
                               prescribedLoad: "RPE8", percentOneRM: nil)])
            ])
        ])
    ])
    let block = BlockBuilder.makeBlock(from: parsed)
    #expect(block.tabName == "Block 27")
    #expect(block.weeks.first?.sessions.first?.exercises.first?.cadence == "0:3:0")
    #expect(block.weeks.first?.sessions.first?.exercises.first?.sets.first?.state == .pending)
}
```

- [ ] **Step 2: Run test to verify it fails** — Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

enum BlockBuilder {
    static func makeBlock(from p: ParsedBlockModel) -> Block {
        let block = Block(tabName: p.tabName, squatTM: nil, benchTM: nil, deadliftTM: nil)
        block.weeks = p.weeks.map { pw in
            let week = Week(number: pw.number)
            week.sessions = pw.days.map { pd in
                let session = Session(dayNumber: pd.dayNumber, date: pd.date)
                session.exercises = pd.exercises.enumerated().map { (i, pe) in
                    let ex = Exercise(name: pe.name, baseName: pe.baseName, cadence: pe.cadence, coachNote: pe.coachNote, order: i)
                    ex.sets = pe.sets.map {
                        ExerciseSet(index: $0.index, prescribedReps: $0.prescribedReps,
                                    prescribedLoad: $0.prescribedLoad, percentOneRM: $0.percentOneRM, state: .pending)
                    }
                    return ex
                }
                return session
            }
            return week
        }
        return block
    }
}
```

- [ ] **Step 4: Run test to verify it passes** — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WorkoutTracker/Parsing/BlockBuilder.swift WorkoutTrackerTests/BlockBuilderTests.swift
git commit -m "feat: build SwiftData Block graph from parsed values"
```

---

## Task 13: Session Progress Tracker — current session/week

**Files:** Create `WorkoutTracker/Progress/SessionProgressTracker.swift`; Test `WorkoutTrackerTests/SessionProgressTrackerTests.swift`.

For Plan 1 (no logging yet) "logged" means a set whose `state == .logged`. The tracker derives the current session as the latest-ordered session containing a logged set, else the very first session.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import SwiftData
@testable import WorkoutTracker

@MainActor
private func makeBlock() -> Block {
    let parsed = ParsedBlockModel(tabName: "Block 27", weeks: (1...2).map { w in
        ParsedWeek(number: w, days: (1...4).map { d in
            ParsedSession(dayNumber: d, date: nil, exercises: [
                ParsedExercise(name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil,
                    sets: [ParsedSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: nil)])
            ])
        })
    })
    return BlockBuilder.makeBlock(from: parsed)
}

@MainActor
@Test func currentSessionIsLatestWithALoggedSet() {
    let block = makeBlock()
    // Mark Week 1 / Day 3's only set as logged.
    block.weeks[0].sessions[2].exercises[0].sets[0].state = .logged
    let tracker = SessionProgressTracker()
    let current = tracker.currentSession(in: block)
    #expect(current?.week?.number == 1)
    #expect(current?.dayNumber == 3)
    #expect(tracker.currentWeek(in: block)?.number == 1)
}

@MainActor
@Test func fallsBackToFirstSessionWhenNothingLogged() {
    let block = makeBlock()
    let current = SessionProgressTracker().currentSession(in: block)
    #expect(current?.week?.number == 1)
    #expect(current?.dayNumber == 1)
}
```

- [ ] **Step 2: Run test to verify it fails** — Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

struct SessionProgressTracker {
    /// Order index across the block: (week-1)*4 + day.
    private func order(_ s: Session) -> Int { ((s.week?.number ?? 1) - 1) * 4 + s.dayNumber }

    private func allSessions(_ block: Block) -> [Session] {
        block.weeks.flatMap { $0.sessions }.sorted { order($0) < order($1) }
    }

    func currentSession(in block: Block) -> Session? {
        let sessions = allSessions(block)
        let logged = sessions.filter { s in
            s.exercises.contains { $0.sets.contains { $0.state == .logged } }
        }
        return logged.last ?? sessions.first
    }

    func currentWeek(in block: Block) -> Week? {
        currentSession(in: block)?.week
    }
}
```

- [ ] **Step 4: Run test to verify it passes** — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WorkoutTracker/Progress/SessionProgressTracker.swift WorkoutTrackerTests/SessionProgressTrackerTests.swift
git commit -m "feat: derive current session and week"
```

---

## Task 14: `SheetsClient` protocol + DTOs

**Files:** Modify `WorkoutTracker/Sheets/SheetsClient.swift`.

- [ ] **Step 1: Add the protocol (no test — it's a seam; the stub is exercised in Task 16)**

```swift
import Foundation

/// All Sheets network access goes through this seam so sync is testable with a stub.
protocol SheetsClient: Sendable {
    /// All sheet/tab titles in the spreadsheet.
    func listTabTitles(spreadsheetId: String) async throws -> [String]
    /// The full grid of one tab as ragged rows of formatted string values.
    func fetchTab(spreadsheetId: String, tabName: String) async throws -> SheetGrid
}

enum SheetsError: Error, Equatable {
    case notAuthorized
    case http(Int)
    case malformedResponse
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `xcodebuild -scheme WorkoutTracker -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add WorkoutTracker/Sheets/SheetsClient.swift
git commit -m "feat: add SheetsClient protocol and error type"
```

---

## Task 15: GoogleAuth wrapper + GoogleSheetsClient

**Files:** Create `WorkoutTracker/Sheets/GoogleAuth.swift`, `WorkoutTracker/Sheets/GoogleSheetsClient.swift`.

This task is I/O against Google; it's verified by the manual smoke test in Task 21 (not unit-tested). Uses GoogleSignIn 8.x APIs and the Sheets REST v4 endpoints with `valueRenderOption=FORMATTED_VALUE` so every cell arrives as a string.

- [ ] **Step 1: Implement `GoogleAuth.swift`**

```swift
import Foundation
import GoogleSignIn

@MainActor
enum GoogleAuth {
    static let scope = "https://www.googleapis.com/auth/spreadsheets"

    static func restorePreviousSignIn() async -> Bool {
        await withCheckedContinuation { cont in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, _ in cont.resume(returning: user != nil) }
        }
    }

    static func signIn(presenting vc: UIViewController) async throws {
        try await GIDSignIn.sharedInstance.signIn(withPresenting: vc, hint: nil, additionalScopes: [scope])
    }

    static func signOut() { GIDSignIn.sharedInstance.signOut() }

    /// A fresh access token, refreshing if needed.
    static func accessToken() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else { throw SheetsError.notAuthorized }
        let refreshed = try await user.refreshTokensIfNeeded()
        return refreshed.accessToken.tokenString
    }
}
```

- [ ] **Step 2: Implement `GoogleSheetsClient.swift`**

```swift
import Foundation

struct GoogleSheetsClient: SheetsClient {
    private let tokenProvider: @Sendable () async throws -> String

    init(tokenProvider: @escaping @Sendable () async throws -> String = { try await GoogleAuth.accessToken() }) {
        self.tokenProvider = tokenProvider
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)?fields=sheets.properties.title")!
        let data = try await get(url)
        struct Resp: Decodable { struct S: Decodable { struct P: Decodable { let title: String }; let properties: P }; let sheets: [S] }
        return (try JSONDecoder().decode(Resp.self, from: data)).sheets.map { $0.properties.title }
    }

    func fetchTab(spreadsheetId: String, tabName: String) async throws -> SheetGrid {
        let range = tabName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tabName
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(spreadsheetId)/values/\(range)?valueRenderOption=FORMATTED_VALUE&majorDimension=ROWS")!
        let data = try await get(url)
        struct Resp: Decodable { let values: [[String]]? }
        return (try JSONDecoder().decode(Resp.self, from: data)).values ?? []
    }

    private func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(try await tokenProvider())", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw SheetsError.malformedResponse }
        guard (200..<300).contains(http.statusCode) else { throw SheetsError.http(http.statusCode) }
        return data
    }
}
```

- [ ] **Step 3: Build** — Run the build command from Task 14 Step 2. Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add WorkoutTracker/Sheets/GoogleAuth.swift WorkoutTracker/Sheets/GoogleSheetsClient.swift
git commit -m "feat: GoogleSignIn auth wrapper and Sheets REST client"
```

---

## Task 16: SyncCoordinator — read-path state machine

**Files:** Create `WorkoutTracker/Stores/SyncCoordinator.swift`; Test `WorkoutTrackerTests/SyncCoordinatorTests.swift`.

Plan-1 states only: `idle`, `syncing`, `offline`, `conflict` (parse warning). No queue/flush (Plan 2).

- [ ] **Step 1: Write the failing test (with a stub client)**

```swift
import Testing
import SwiftData
@testable import WorkoutTracker

private struct StubClient: SheetsClient {
    var titles: [String]
    var grid: SheetGrid
    var failOffline = false
    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        if failOffline { throw URLError(.notConnectedToInternet) }
        return titles
    }
    func fetchTab(spreadsheetId: String, tabName: String) async throws -> SheetGrid { grid }
}

@MainActor
@Test func syncFetchesParsesAndPersistsCurrentBlock() async throws {
    let container = try ModelContainer(for: Block.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let grid = gridFromA1([
        "C12": "Day 1", "S12": "Day 2", "AI12": "Day 3", "AX12": "Day 4",
        "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
        "C15": "Squat", "D15": "1", "F15": "5", "H15": "RPE8",
    ], rows: 20, cols: 60)
    let client = StubClient(titles: ["Intro", "Block 27"], grid: grid)
    let sync = SyncCoordinator(client: client, context: container.mainContext)

    await sync.sync(spreadsheetId: "sid")

    #expect(sync.state == .idle)
    let blocks = try container.mainContext.fetch(FetchDescriptor<Block>())
    #expect(blocks.count == 1)
    #expect(blocks[0].tabName == "Block 27")
}

@MainActor
@Test func syncGoesOfflineOnNetworkError() async throws {
    let container = try ModelContainer(for: Block.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let client = StubClient(titles: [], grid: [], failOffline: true)
    let sync = SyncCoordinator(client: client, context: container.mainContext)
    await sync.sync(spreadsheetId: "sid")
    #expect(sync.state == .offline)
}
```

- [ ] **Step 2: Run test to verify it fails** — Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation
import SwiftData

@MainActor
@Observable
final class SyncCoordinator {
    enum State: Equatable { case idle, syncing, offline, conflict([String]) }
    private(set) var state: State = .idle

    private let client: SheetsClient
    private let context: ModelContext

    init(client: SheetsClient, context: ModelContext) {
        self.client = client
        self.context = context
    }

    func sync(spreadsheetId: String) async {
        state = .syncing
        do {
            let titles = try await client.listTabTitles(spreadsheetId: spreadsheetId)
            guard let tab = currentBlockTab(from: titles) else {
                state = .conflict(["No block tab found in the spreadsheet"]); return
            }
            let grid = try await client.fetchTab(spreadsheetId: spreadsheetId, tabName: tab)
            let parsed = SheetParser().parse(grid: grid, tabName: tab)
            replacePersistedBlock(with: BlockBuilder.makeBlock(from: parsed.block))
            state = parsed.warnings.isEmpty ? .idle : .conflict(parsed.warnings)
        } catch {
            state = .offline
        }
    }

    /// One Block at a time: delete the existing block(s), insert the fresh one.
    private func replacePersistedBlock(with block: Block) {
        for existing in (try? context.fetch(FetchDescriptor<Block>())) ?? [] { context.delete(existing) }
        context.insert(block)
        try? context.save()
    }
}
```

- [ ] **Step 4: Run test to verify it passes** — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WorkoutTracker/Stores/SyncCoordinator.swift WorkoutTrackerTests/SyncCoordinatorTests.swift
git commit -m "feat: SyncCoordinator read path (fetch/parse/persist) with states"
```

---

## Task 17: WorkoutStore — load block + current/displayed session

**Files:** Create `WorkoutTracker/Stores/WorkoutStore.swift`; Test `WorkoutTrackerTests/WorkoutStoreTests.swift`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import SwiftData
@testable import WorkoutTracker

@MainActor
@Test func loadsBlockAndDefaultsDisplayedToCurrent() throws {
    let container = try ModelContainer(for: Block.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let ctx = container.mainContext
    let parsed = ParsedBlockModel(tabName: "Block 27", weeks: (1...1).map { w in
        ParsedWeek(number: w, days: (1...4).map { d in
            ParsedSession(dayNumber: d, date: nil, exercises: [])
        })
    })
    ctx.insert(BlockBuilder.makeBlock(from: parsed)); try ctx.save()

    let store = WorkoutStore(context: ctx)
    store.reload()

    #expect(store.block?.tabName == "Block 27")
    #expect(store.displayedSession?.dayNumber == 1)   // defaults to current
    store.show(week: 1, day: 3)
    #expect(store.displayedSession?.dayNumber == 3)
}
```

- [ ] **Step 2: Run test to verify it fails** — Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation
import SwiftData

@MainActor
@Observable
final class WorkoutStore {
    private(set) var block: Block?
    private(set) var displayedSession: Session?

    private let context: ModelContext
    private let tracker = SessionProgressTracker()

    init(context: ModelContext) { self.context = context }

    var currentSession: Session? { block.flatMap { tracker.currentSession(in: $0) } }
    var isViewingLiveEdge: Bool { displayedSession?.persistentModelID == currentSession?.persistentModelID }

    func reload() {
        block = try? context.fetch(FetchDescriptor<Block>()).first
        displayedSession = currentSession
    }

    func show(week: Int, day: Int) {
        displayedSession = block?.weeks.first { $0.number == week }?.sessions.first { $0.dayNumber == day }
    }
}
```

- [ ] **Step 4: Run test to verify it passes** — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WorkoutTracker/Stores/WorkoutStore.swift WorkoutTrackerTests/WorkoutStoreTests.swift
git commit -m "feat: WorkoutStore loads block and tracks displayed session"
```

---

## Task 18: SettingsStore

**Files:** Create `WorkoutTracker/Stores/SettingsStore.swift`; Test `WorkoutTrackerTests/SettingsStoreTests.swift`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import WorkoutTracker

@MainActor
@Test func isConfiguredRequiresSpreadsheetIdAndAuth() {
    let store = SettingsStore(defaults: UserDefaults(suiteName: "test.\(UUID())")!)
    store.isSignedIn = true
    #expect(store.isConfigured == false)           // no URL yet
    store.setSheetURL("https://docs.google.com/spreadsheets/d/SHEET123/edit")
    #expect(store.spreadsheetId == "SHEET123")
    #expect(store.isConfigured == true)
}
```

- [ ] **Step 2: Run test to verify it fails** — Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

@MainActor
@Observable
final class SettingsStore {
    var isSignedIn = false
    private(set) var spreadsheetId: String?
    private let defaults: UserDefaults
    private let key = "spreadsheetId"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.spreadsheetId = defaults.string(forKey: key)
    }

    var isConfigured: Bool { isSignedIn && spreadsheetId != nil }

    /// Stores the spreadsheet id parsed from a pasted Sheet URL. Returns false if unparseable.
    @discardableResult
    func setSheetURL(_ url: String) -> Bool {
        guard let id = extractSpreadsheetId(from: url) else { return false }
        spreadsheetId = id
        defaults.set(id, forKey: key)
        return true
    }
}
```

- [ ] **Step 4: Run test to verify it passes** — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add WorkoutTracker/Stores/SettingsStore.swift WorkoutTrackerTests/SettingsStoreTests.swift
git commit -m "feat: SettingsStore with persisted spreadsheet id and isConfigured"
```

---

## Task 19: App entry, ModelContainer, environment wiring

**Files:** Replace `WorkoutTracker/WorkoutTrackerApp.swift`; Create `WorkoutTracker/Views/RootView.swift`.

- [ ] **Step 1: Implement `WorkoutTrackerApp.swift`**

```swift
import SwiftUI
import SwiftData
import GoogleSignIn

@main
struct WorkoutTrackerApp: App {
    let container: ModelContainer
    @State private var settings: SettingsStore
    @State private var workout: WorkoutStore
    @State private var sync: SyncCoordinator

    init() {
        let container = try! ModelContainer(for: Block.self)
        self.container = container
        let ctx = container.mainContext
        _settings = State(initialValue: SettingsStore())
        _workout = State(initialValue: WorkoutStore(context: ctx))
        _sync = State(initialValue: SyncCoordinator(client: GoogleSheetsClient(), context: ctx))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(workout)
                .environment(sync)
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
                .task {
                    settings.isSignedIn = await GoogleAuth.restorePreviousSignIn()
                }
        }
        .modelContainer(container)
    }
}
```

- [ ] **Step 2: Implement `RootView.swift`**

```swift
import SwiftUI

struct RootView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        if settings.isConfigured {
            SessionView()
        } else {
            OnboardingView()
        }
    }
}
```

- [ ] **Step 3: Build** — Expected: build fails only because `OnboardingView`/`SessionView` don't exist yet (next tasks). That's acceptable here; do not commit until Task 21.

---

## Task 20: OnboardingView

**Files:** Create `WorkoutTracker/Views/OnboardingView.swift`.

- [ ] **Step 1: Implement**

```swift
import SwiftUI
import GoogleSignInSwift

struct OnboardingView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var urlText = ""
    @State private var urlError = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Connect your training sheet").font(.title2.bold())

            GoogleSignInButton {
                Task {
                    guard let vc = topViewController() else { return }
                    do { try await GoogleAuth.signIn(presenting: vc); settings.isSignedIn = true }
                    catch { settings.isSignedIn = false }
                }
            }
            .frame(maxWidth: 280)
            .opacity(settings.isSignedIn ? 0.4 : 1)

            if settings.isSignedIn {
                TextField("Paste your Google Sheet URL", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if urlError { Text("That doesn't look like a Sheet URL").font(.caption).foregroundStyle(.red) }
                Button("Save") { urlError = !settings.setSheetURL(urlText) }
                    .buttonStyle(.borderedProminent)
                    .disabled(urlText.isEmpty)
            }
        }
        .padding()
    }
}

@MainActor
func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
    var top = scene?.keyWindow?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
}
```

- [ ] **Step 2: Build** — still expected to fail only on missing `SessionView`. Proceed.

---

## Task 21: SessionView (read-only) + run

**Files:** Create `WorkoutTracker/Views/SessionView.swift`.

- [ ] **Step 1: Implement**

```swift
import SwiftUI

struct SessionView: View {
    @Environment(WorkoutStore.self) private var workout
    @Environment(SyncCoordinator.self) private var sync
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        NavigationStack {
            Group {
                if let session = workout.displayedSession {
                    List {
                        ForEach(session.exercises.sorted(by: { $0.order < $1.order }), id: \.persistentModelID) { ex in
                            Section {
                                if let note = ex.coachNote { Text(note).font(.callout).foregroundStyle(.secondary) }
                                ForEach(ex.sets.sorted(by: { $0.index < $1.index }), id: \.persistentModelID) { set in
                                    HStack {
                                        Text("Set \(set.index + 1)")
                                        Spacer()
                                        Text(set.prescribedReps).foregroundStyle(.secondary)
                                        Text(set.prescribedLoad).foregroundStyle(.secondary)
                                    }.font(.subheadline)
                                }
                            } header: {
                                Text(ex.cadence.map { "\($0)  " } ?? "") + Text(ex.baseName).bold()
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("No session yet", systemImage: "dumbbell",
                        description: Text("Pull to refresh to sync your sheet."))
                }
            }
            .navigationTitle(breadcrumb)
            .refreshable {
                if let id = settings.spreadsheetId { await sync.sync(spreadsheetId: id); workout.reload() }
            }
            .task {
                workout.reload()
                if workout.block == nil, let id = settings.spreadsheetId {
                    await sync.sync(spreadsheetId: id); workout.reload()
                }
            }
        }
    }

    private var breadcrumb: String {
        guard let s = workout.displayedSession else { return "Workout" }
        return "Block · W\(s.week?.number ?? 0) D\(s.dayNumber)"
    }
}
```

- [ ] **Step 2: Build + run all tests**

Run: `xcodebuild -scheme WorkoutTracker -destination 'platform=iOS Simulator,name=iPhone 16' test`
Expected: build succeeds; all unit tests pass.

- [ ] **Step 3: Manual smoke test (golden path)**

Launch in the simulator. Onboarding → tap Sign in with Google (use the athlete's account) → paste the real Sheet URL → Save. App should sync, then show Block 27's current session with exercises, prescribed sets/reps/load, cadence in the header, and coach notes. Pull-to-refresh re-syncs. Confirm a no-network launch still shows the last session (offline-first).

- [ ] **Step 4: Commit**

```bash
git add WorkoutTracker/Views WorkoutTracker/WorkoutTrackerApp.swift
git commit -m "feat: read-only SessionView, onboarding, and app wiring"
```

---

## Spec coverage check (self-review)

- **ADR 0001** (sheet as source of truth, local-first): sync fetches→parses→persists; offline cold launch reads the persisted Block. ✓
- **ADR 0003** (dynamic targeting): `resolveDayColumns` scans header strings within each day span; nothing hardcoded. ✓ (write-side verification is Plan 2.)
- **New-block detection** (PRD #32): `currentBlockTab` handles `Block N` / `Block - N`. ✓
- **Onboarding** (PRD #33–34): Google sign-in + paste URL. ✓
- **Read-only display** (PRD #1–3, #35–36): SessionView shows prescribed sets/reps/load + AMRAP/range strings + coach notes. ✓
- **Out of scope here (later plans):** logging/write-back, conflict verify, Last Performed, Load Suggestions, Open Exercises, Block Overview grid, Move On, Last-Set-RPE. (Plans 2–4.)

**Deferred to Plan 2 and noted in code:** `ExerciseSet.setLogData` exists but is unused until Plan 2 reads logs from the Notes continuation rows and sets `state = .logged`. Until then, `currentSession` falls back to the first session (acceptable for a read-only viewer).
