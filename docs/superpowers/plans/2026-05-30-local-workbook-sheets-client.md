# Local Workbook Sheets Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a shared test-only local workbook `SheetsClient` and one read-after-write round-trip test that proves `SyncCoordinator` and `SheetWriter` can flush pending writes, fetch the mutated Sheet grid, parse it again, and observe final domain state without live Google access.

**Architecture:** Keep production code unchanged and add the confidence layer entirely under `Tests/Support` and `Tests/Unit`. `LocalWorkbookSheetsClient` is an `actor` that stores tab-title-to-`SheetGrid` state, parses the A1 ranges emitted by `singleCellRange(tabName:row:col:)`, stages batch writes against copied workbook state, and commits only after every update is valid. The first workflow test uses existing `SyncCoordinator`, `SheetWriter`, `SheetParser`, SwiftData in-memory storage, and workbook reads as the assertion boundary.

**Tech Stack:** Swift 6, Swift Testing (`@Test`, `#expect`, `#require`), SwiftData in-memory `ModelContainer`, existing `SheetsClient`, `SheetGrid`, `SheetWriter`, `SyncCoordinator`, and `SheetParser`. Spec: `docs/specs/2026-05-30-local-workbook-sheets-client.md`.

---

## Before Starting

- Confirm the worktree is dirty-safe: do not revert or reformat unrelated changes.
- Do not edit production files for this spec.
- Use a feature branch before implementation, for example:

```bash
git checkout -b codex/local-workbook-sheets-client
```

Expected: branch switches successfully. If the branch already exists, use `git switch codex/local-workbook-sheets-client`.

## File Structure

- Create: `Tests/Support/LocalWorkbookSheetsClient.swift`
  - Test-only `SheetsClient` implementation.
  - Owns workbook state as `[String: SheetGrid]`.
  - Supports `listTabTitles`, `fetchTab`, single-range writes, multi-range batch writes, quoted tab names, blank writes, grid growth, rectangular range writes, and recorded batch inspection.
  - Does not emulate Google `USER_ENTERED`, formulas, locale, date parsing, Drive lifecycle, auth, or network.
- Create: `Tests/Unit/LocalWorkbookSheetsClientTests.swift`
  - Focused unit tests for the support client contract.
  - Covers read-after-write, blank writes, quoted tab names, growth, rectangular writes, recorded batches, and atomic failed batches.
- Modify: `Tests/Support/SheetGridFixture.swift`
  - Add one named Coach Note layout fixture used by the local workbook round-trip test.
- Create: `Tests/Unit/SyncCoordinatorLocalWorkbookRoundTripTests.swift`
  - One high-risk write-path round-trip test.
  - Seeds the workbook, inserts `PendingWrite` records, runs `SyncCoordinator.flushPending(spreadsheetId:)`, fetches the mutated tab through `SheetsClient`, reparses with `SheetParser`, and asserts protected Coach Note, continuation Set Logs, Last Set RPE cell, parsed Set states, recorded batch shape, and pending-write deletion.

## Task 1: Add Local Workbook Client Read/Single-Write Contract

This task creates the shared support client and proves the basic workbook boundary: seeded tab listing, tab fetches, single-cell writes, blank writes, quoted tab names, and dynamic grid growth.

**Files:**
- Create: `Tests/Support/LocalWorkbookSheetsClient.swift`
- Create: `Tests/Unit/LocalWorkbookSheetsClientTests.swift`

- [ ] **Step 1: Create the focused tests for the basic contract**

Create `Tests/Unit/LocalWorkbookSheetsClientTests.swift` with this initial content:

```swift
import Testing

@testable import WorkoutTracker

@Test func localWorkbookListsAndFetchesSeededTabs() async throws {
    let block27 = gridFromA1(["A1": "Block 27 marker"], rows: 2, cols: 2)
    let block26 = gridFromA1(["B2": "Block 26 marker"], rows: 3, cols: 3)
    let client = LocalWorkbookSheetsClient(
        tabs: [
            "Block 27": block27,
            "Block 26": block26
        ]
    )

    let titles = try await client.listTabTitles(spreadsheetId: "sid")
    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")

    #expect(titles == ["Block 26", "Block 27"])
    #expect(fetched == block27)
}

@Test func localWorkbookSingleCellWritePersistsForLaterFetchAndGrowsGrid() async throws {
    let client = LocalWorkbookSheetsClient(
        tabs: ["Block 27": gridFromA1(["A1": "seed"], rows: 1, cols: 1)]
    )

    try await client.updateCells(
        spreadsheetId: "sid",
        range: "'Block 27'!C3",
        values: [["grown"]]
    )

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    #expect(fetched.cell(row: 0, col: 0) == "seed")
    #expect(fetched.cell(row: 2, col: 2) == "grown")
}

@Test func localWorkbookBlankWritePersistsEmptyString() async throws {
    let client = LocalWorkbookSheetsClient(
        tabs: ["Block 27": gridFromA1(["K15": "185x5@8"], rows: 20, cols: 12)]
    )

    try await client.updateCells(
        spreadsheetId: "sid",
        range: "'Block 27'!K15",
        values: [[""]]
    )

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    #expect(fetched.cell(row: 14, col: 10) == "")
}

@Test func localWorkbookParsesQuotedTabNameWithEscapedApostrophe() async throws {
    let client = LocalWorkbookSheetsClient(
        tabs: ["Coach's Block": gridFromA1([:], rows: 1, cols: 1)]
    )

    try await client.updateCells(
        spreadsheetId: "sid",
        range: "'Coach''s Block'!B2",
        values: [["quoted"]]
    )

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Coach's Block")
    #expect(fetched.cell(row: 1, col: 1) == "quoted")
}
```

- [ ] **Step 2: Run the basic client tests and verify they fail**

Run:

```bash
swift test --filter LocalWorkbookSheetsClientTests
```

Expected: FAIL at compile time with an error like `cannot find 'LocalWorkbookSheetsClient' in scope`.

- [ ] **Step 3: Create the minimal local workbook implementation**

Create `Tests/Support/LocalWorkbookSheetsClient.swift` with this content:

```swift
@testable import WorkoutTracker

enum LocalWorkbookSheetsClientError: Error, Equatable, Sendable, CustomStringConvertible {
    case unknownTab(String)
    case malformedRange(String)
    case unsupportedValues(String)

    var description: String {
        switch self {
        case .unknownTab(let tab):
            "Unknown tab: \(tab)"
        case .malformedRange(let range):
            "Malformed A1 range: \(range)"
        case .unsupportedValues(let details):
            "Unsupported values: \(details)"
        }
    }
}

actor LocalWorkbookSheetsClient: SheetsClient {
    private var tabs: [String: SheetGrid]
    private(set) var recordedBatches: [[SheetValueRangeUpdate]] = []

    init(spreadsheetId: String = "sid", tabs: [String: SheetGrid]) {
        self.tabs = tabs
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        tabs.keys.sorted()
    }

    func fetchTab(spreadsheetId: String, tabName: String) async throws -> SheetGrid {
        guard let grid = tabs[tabName] else {
            throw LocalWorkbookSheetsClientError.unknownTab(tabName)
        }
        return grid
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {
        try await updateCells(
            spreadsheetId: spreadsheetId,
            updates: [SheetValueRangeUpdate(range: range, values: values)]
        )
    }

    func updateCells(spreadsheetId: String, updates: [SheetValueRangeUpdate]) async throws {
        let staged = try Self.applying(updates, to: tabs)
        recordedBatches.append(updates)
        tabs = staged
    }
}

private extension LocalWorkbookSheetsClient {
    struct ParsedRange {
        let tabName: String
        let startRow: Int
        let startCol: Int
        let rowCount: Int
        let colCount: Int
    }

    static func applying(
        _ updates: [SheetValueRangeUpdate],
        to workbook: [String: SheetGrid]
    ) throws -> [String: SheetGrid] {
        var staged = workbook
        for update in updates {
            let range = try parseRange(update.range)
            guard let grid = staged[range.tabName] else {
                throw LocalWorkbookSheetsClientError.unknownTab(range.tabName)
            }
            staged[range.tabName] = try applying(update.values, to: grid, range: range)
        }
        return staged
    }

    static func applying(
        _ values: [[String]],
        to grid: SheetGrid,
        range: ParsedRange
    ) throws -> SheetGrid {
        guard values.count == range.rowCount else {
            throw LocalWorkbookSheetsClientError.unsupportedValues(
                "Expected \(range.rowCount) row(s), got \(values.count)"
            )
        }
        guard values.allSatisfy({ $0.count == range.colCount }) else {
            throw LocalWorkbookSheetsClientError.unsupportedValues(
                "Expected every row to contain \(range.colCount) value(s)"
            )
        }

        var updated = grid
        let requiredRows = range.startRow + range.rowCount
        if requiredRows > updated.count {
            updated.append(contentsOf: SheetGrid(repeating: [], count: requiredRows - updated.count))
        }

        for rowOffset in 0..<range.rowCount {
            let rowIndex = range.startRow + rowOffset
            let requiredCols = range.startCol + range.colCount
            if requiredCols > updated[rowIndex].count {
                updated[rowIndex].append(
                    contentsOf: [String](repeating: "", count: requiredCols - updated[rowIndex].count)
                )
            }

            for colOffset in 0..<range.colCount {
                updated[rowIndex][range.startCol + colOffset] = values[rowOffset][colOffset]
            }
        }

        return updated
    }

    static func parseRange(_ range: String) throws -> ParsedRange {
        let split = try splitA1Range(range)
        let references = split.reference
            .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            .map(String.init)
        guard references.count == 1 || references.count == 2 else {
            throw LocalWorkbookSheetsClientError.malformedRange(range)
        }

        let start = try parseCellReference(references[0], sourceRange: range)
        let end: (row: Int, col: Int)
        if references.count == 2 {
            end = try parseCellReference(references[1], sourceRange: range)
        } else {
            end = start
        }
        guard end.row >= start.row, end.col >= start.col else {
            throw LocalWorkbookSheetsClientError.malformedRange(range)
        }

        return ParsedRange(
            tabName: split.tabName,
            startRow: start.row,
            startCol: start.col,
            rowCount: end.row - start.row + 1,
            colCount: end.col - start.col + 1
        )
    }

    static func splitA1Range(_ range: String) throws -> (tabName: String, reference: String) {
        var inQuotedTab = false
        var index = range.startIndex
        while index < range.endIndex {
            let character = range[index]
            if character == "'" {
                let next = range.index(after: index)
                if inQuotedTab, next < range.endIndex, range[next] == "'" {
                    index = range.index(after: next)
                    continue
                }
                inQuotedTab.toggle()
            } else if character == "!", !inQuotedTab {
                let rawTabName = String(range[..<index])
                let referenceStart = range.index(after: index)
                let reference = String(range[referenceStart...])
                guard !rawTabName.isEmpty, !reference.isEmpty else {
                    throw LocalWorkbookSheetsClientError.malformedRange(range)
                }
                return (try unquotedTabName(rawTabName, sourceRange: range), reference)
            }
            index = range.index(after: index)
        }

        throw LocalWorkbookSheetsClientError.malformedRange(range)
    }

    static func unquotedTabName(_ raw: String, sourceRange: String) throws -> String {
        guard raw.hasPrefix("'") || raw.hasSuffix("'") else { return raw }
        guard raw.hasPrefix("'"), raw.hasSuffix("'"), raw.count >= 2 else {
            throw LocalWorkbookSheetsClientError.malformedRange(sourceRange)
        }

        let inner = raw.dropFirst().dropLast()
        return inner.replacingOccurrences(of: "''", with: "'")
    }

    static func parseCellReference(_ reference: String, sourceRange: String) throws -> (row: Int, col: Int) {
        let upper = reference.uppercased()
        var letters = ""
        var digits = ""

        for character in upper {
            if character.isLetter, digits.isEmpty {
                letters.append(character)
            } else if character.isNumber {
                digits.append(character)
            } else {
                throw LocalWorkbookSheetsClientError.malformedRange(sourceRange)
            }
        }

        guard !letters.isEmpty, !digits.isEmpty, let rowNumber = Int(digits), rowNumber > 0 else {
            throw LocalWorkbookSheetsClientError.malformedRange(sourceRange)
        }

        var colNumber = 0
        for byte in letters.utf8 {
            guard byte >= 65, byte <= 90 else {
                throw LocalWorkbookSheetsClientError.malformedRange(sourceRange)
            }
            colNumber = colNumber * 26 + Int(byte - 64)
        }

        return (row: rowNumber - 1, col: colNumber - 1)
    }
}
```

- [ ] **Step 4: Run the basic client tests and verify they pass**

Run:

```bash
swift test --filter LocalWorkbookSheetsClientTests
```

Expected: PASS for the four `LocalWorkbookSheetsClientTests` tests.

- [ ] **Step 5: Commit the basic local workbook contract**

Run:

```bash
git add Tests/Support/LocalWorkbookSheetsClient.swift Tests/Unit/LocalWorkbookSheetsClientTests.swift
git commit -m "test: add local workbook sheets client"
```

Expected: commit succeeds and includes only those two files.

## Task 2: Add Batch Atomicity and Rectangular Range Coverage

This task expands the local workbook tests to prove the behavior the pending-write deletion model depends on: successful batches are visible after commit, failed batches leave every tab unchanged, and invalid value dimensions throw before mutation.

**Files:**
- Modify: `Tests/Unit/LocalWorkbookSheetsClientTests.swift`
- Modify: `Tests/Support/LocalWorkbookSheetsClient.swift`

- [ ] **Step 1: Add batch and failure-path tests**

Append these tests to `Tests/Unit/LocalWorkbookSheetsClientTests.swift`:

```swift
@Test func localWorkbookBatchWriteCommitsEveryUpdateAndRecordsTheBatch() async throws {
    let client = LocalWorkbookSheetsClient(
        tabs: [
            "Block 27": gridFromA1(
                [
                    "A1": "old A",
                    "B1": "old B"
                ],
                rows: 1,
                cols: 2
            )
        ]
    )

    try await client.updateCells(
        spreadsheetId: "sid",
        updates: [
            SheetValueRangeUpdate(range: "'Block 27'!A1", values: [["new A"]]),
            SheetValueRangeUpdate(range: "'Block 27'!B1", values: [["new B"]])
        ]
    )

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    let batches = await client.recordedBatches

    #expect(fetched.cell(row: 0, col: 0) == "new A")
    #expect(fetched.cell(row: 0, col: 1) == "new B")
    #expect(batches.count == 1)
    #expect(batches[0].map(\.range) == ["'Block 27'!A1", "'Block 27'!B1"])
}

@Test func localWorkbookRectangularWritePersistsEveryCell() async throws {
    let client = LocalWorkbookSheetsClient(
        tabs: ["Block 27": gridFromA1([:], rows: 1, cols: 1)]
    )

    try await client.updateCells(
        spreadsheetId: "sid",
        range: "'Block 27'!B2:C3",
        values: [
            ["B2", "C2"],
            ["B3", "C3"]
        ]
    )

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    #expect(fetched.cell(row: 1, col: 1) == "B2")
    #expect(fetched.cell(row: 1, col: 2) == "C2")
    #expect(fetched.cell(row: 2, col: 1) == "B3")
    #expect(fetched.cell(row: 2, col: 2) == "C3")
}

@Test func localWorkbookFailedBatchLeavesWorkbookUnchangedAndUnrecorded() async throws {
    let original = gridFromA1(["A1": "original"], rows: 1, cols: 1)
    let client = LocalWorkbookSheetsClient(tabs: ["Block 27": original])

    await #expect(throws: LocalWorkbookSheetsClientError.unknownTab("Missing")) {
        try await client.updateCells(
            spreadsheetId: "sid",
            updates: [
                SheetValueRangeUpdate(range: "'Block 27'!A1", values: [["changed"]]),
                SheetValueRangeUpdate(range: "'Missing'!A1", values: [["should throw"]])
            ]
        )
    }

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    let batches = await client.recordedBatches
    #expect(fetched == original)
    #expect(batches.isEmpty)
}

@Test func localWorkbookRejectsValueDimensionsWithoutMutatingWorkbook() async throws {
    let original = gridFromA1(["A1": "original"], rows: 1, cols: 1)
    let client = LocalWorkbookSheetsClient(tabs: ["Block 27": original])

    await #expect(
        throws: LocalWorkbookSheetsClientError.unsupportedValues("Expected every row to contain 2 value(s)")
    ) {
        try await client.updateCells(
            spreadsheetId: "sid",
            range: "'Block 27'!A1:B1",
            values: [["only one value"]]
        )
    }

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    let batches = await client.recordedBatches
    #expect(fetched == original)
    #expect(batches.isEmpty)
}

@Test func localWorkbookRejectsMalformedRangeWithoutMutatingWorkbook() async throws {
    let original = gridFromA1(["A1": "original"], rows: 1, cols: 1)
    let client = LocalWorkbookSheetsClient(tabs: ["Block 27": original])

    await #expect(throws: LocalWorkbookSheetsClientError.malformedRange("Block 27")) {
        try await client.updateCells(
            spreadsheetId: "sid",
            range: "Block 27",
            values: [["changed"]]
        )
    }

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    #expect(fetched == original)
    #expect(await client.recordedBatches.isEmpty)
}
```

- [ ] **Step 2: Run the expanded local workbook tests**

Run:

```bash
swift test --filter LocalWorkbookSheetsClientTests
```

Expected: PASS. The Task 1 implementation should already satisfy these contracts; if a test fails, make the smallest correction in `Tests/Support/LocalWorkbookSheetsClient.swift` and rerun this same command.

- [ ] **Step 3: Commit batch atomicity coverage**

Run:

```bash
git add Tests/Support/LocalWorkbookSheetsClient.swift Tests/Unit/LocalWorkbookSheetsClientTests.swift
git commit -m "test: cover local workbook batch atomicity"
```

Expected: commit succeeds. If `Tests/Support/LocalWorkbookSheetsClient.swift` was unchanged because Task 1 already satisfied the tests, the commit may include only `Tests/Unit/LocalWorkbookSheetsClientTests.swift`.

## Task 3: Add the SyncCoordinator Local Workbook Round-Trip Test

This task adds the main confidence-layer test. It must assert through the workbook's public `SheetsClient` behavior and parsed domain state, not by inspecting internal `SyncCoordinator` implementation details.

**Files:**
- Modify: `Tests/Support/SheetGridFixture.swift`
- Create: `Tests/Unit/SyncCoordinatorLocalWorkbookRoundTripTests.swift`

- [ ] **Step 1: Add the shared Coach Note fixture**

Append this fixture to `Tests/Support/SheetGridFixture.swift`:

```swift
/// Day 1/2 week with a two-set Incline DB Bench Press whose header Notes cell
/// holds a protected AMRAP Coach Note. Set Logs must land on continuation rows,
/// and Last Set RPE must land on the exercise anchor row.
func coachNoteBenchPressRoundTripGrid() -> SheetGrid {
    gridFromA1(
        [
            "C37": "Day 1", "S37": "Day 2",
            "D39": "Sets", "F39": "Reps", "H39": "Load", "I39": "Last set RPE", "K39": "Notes",
            "C51": "2-3:1:0 Incline DB BP", "D51": "2", "F51": "7 - 8", "H51": "RPE8, RF",
            "K51": "AMRAP w/ 0:3:0 BW Push Up",
            "C55": "0:2:0 Hamstring Curl", "D55": "2"
        ],
        rows: 60,
        cols: 30
    )
}
```

- [ ] **Step 2: Create the round-trip test file**

Create `Tests/Unit/SyncCoordinatorLocalWorkbookRoundTripTests.swift` with this content:

```swift
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
private func makeLocalWorkbookRoundTripContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Block.self,
        PendingWrite.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}

private func localWorkbookPendingWrite(
    createdAt: TimeInterval,
    exerciseName: String = "2-3:1:0 Incline DB BP",
    setIndex: Int,
    column: PendingWriteColumn = .notes,
    valueToWrite: String
) -> PendingWrite {
    PendingWrite(
        createdAt: Date(timeIntervalSince1970: createdAt),
        blockTab: "Block 27",
        week: 1,
        day: 1,
        exerciseName: exerciseName,
        setIndex: setIndex,
        column: column,
        operation: .upsert,
        valueToWrite: valueToWrite,
        expectedCurrentValue: ""
    )
}

@MainActor
@Test func localWorkbookRoundTripFlushWritesCoachNoteContinuationLogsAndParsesDomainState() async throws {
    let container = try makeLocalWorkbookRoundTripContainer()
    let context = container.mainContext
    context.insert(
        localWorkbookPendingWrite(
            createdAt: 1,
            setIndex: 0,
            valueToWrite: "100x8@6"
        )
    )
    context.insert(
        localWorkbookPendingWrite(
            createdAt: 2,
            setIndex: 1,
            valueToWrite: "105x7@7"
        )
    )
    context.insert(
        localWorkbookPendingWrite(
            createdAt: 3,
            setIndex: 1,
            column: .lastSetRPE,
            valueToWrite: "7"
        )
    )
    try context.save()

    let client = LocalWorkbookSheetsClient(
        tabs: ["Block 27": coachNoteBenchPressRoundTripGrid()]
    )
    let sync = SyncCoordinator(client: client, context: context)

    await sync.flushPending(spreadsheetId: "sid")

    let updated = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    let parsed = SheetParser().parse(grid: updated, tabName: "Block 27")
    let exercise = try #require(
        parsed.block.weeks.first?.days.first?.exercises.first {
            $0.name == "2-3:1:0 Incline DB BP"
        }
    )
    let firstSet = try #require(exercise.sets.first { $0.index == 0 })
    let secondSet = try #require(exercise.sets.first { $0.index == 1 })
    let batches = await client.recordedBatches

    #expect(updated.cell(row: 50, col: 10) == "AMRAP w/ 0:3:0 BW Push Up")
    #expect(updated.cell(row: 51, col: 10) == "100x8@6")
    #expect(updated.cell(row: 52, col: 10) == "105x7@7")
    #expect(updated.cell(row: 50, col: 8) == "7")
    #expect(exercise.coachNote == "AMRAP w/ 0:3:0 BW Push Up")
    #expect(firstSet.state == .logged)
    #expect(firstSet.setLog?.formatted == "100x8@6")
    #expect(secondSet.state == .logged)
    #expect(secondSet.setLog?.formatted == "105x7@7")
    #expect(parsed.warnings.isEmpty)
    #expect(try context.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    #expect(sync.state == .idle)
    #expect(batches.count == 1)
    #expect(batches[0].map(\.range) == ["'Block 27'!K52", "'Block 27'!K53", "'Block 27'!I51"])
}
```

- [ ] **Step 3: Run the round-trip test**

Run:

```bash
swift test --filter localWorkbookRoundTripFlushWritesCoachNoteContinuationLogsAndParsesDomainState
```

Expected: PASS. The test should perform no Google auth, no live Google Sheets request, and no network request.

- [ ] **Step 4: Commit the round-trip test**

Run:

```bash
git add Tests/Support/SheetGridFixture.swift Tests/Unit/SyncCoordinatorLocalWorkbookRoundTripTests.swift
git commit -m "test: add local workbook sync round trip"
```

Expected: commit succeeds and includes only the fixture addition plus the new round-trip test file.

## Task 4: Verify Existing Write-Path Regressions Still Pass

This task protects the existing batch, conflict, retry, and ordering coverage. Do not replace file-local specialized fakes in this plan; this spec's implementation scope is the shared workbook and one local round-trip confidence test.

**Files:**
- No file changes.

- [ ] **Step 1: Run the local workbook tests**

Run:

```bash
swift test --filter LocalWorkbookSheetsClientTests
```

Expected: PASS.

- [ ] **Step 2: Run the local workbook round-trip test**

Run:

```bash
swift test --filter localWorkbookRoundTripFlushWritesCoachNoteContinuationLogsAndParsesDomainState
```

Expected: PASS.

- [ ] **Step 3: Run existing SyncCoordinator batch-write regressions**

Run:

```bash
swift test --filter SyncCoordinatorBatchWriteTests
```

Expected: PASS. This confirms existing compact aggregate, Coach Note, stale conflict, retry, overlap-splitting, final-RPE batching, and concurrent flush coverage still passes.

- [ ] **Step 4: Run the standard Swift package test gate**

Run:

```bash
swift test
```

Expected: PASS for the full Swift package test suite.

- [ ] **Step 5: Run SwiftLint if available**

Run:

```bash
/bin/zsh -lc 'if command -v swiftlint >/dev/null 2>&1; then swiftlint lint --quiet; else echo "[info] swiftlint not installed - skipping lint"; fi'
```

Expected: no output when SwiftLint passes, or `[info] swiftlint not installed - skipping lint` when the tool is unavailable.

- [ ] **Step 6: Commit any verification-only fix if required**

If Steps 1-5 required small fixes, run:

```bash
git add Tests/Support/LocalWorkbookSheetsClient.swift Tests/Unit/LocalWorkbookSheetsClientTests.swift Tests/Support/SheetGridFixture.swift Tests/Unit/SyncCoordinatorLocalWorkbookRoundTripTests.swift
git commit -m "test: stabilize local workbook write coverage"
```

Expected: commit succeeds only if fixes were made. If no files changed after verification, skip this commit.

## Task 5: Final Review Checklist

Use this checklist before handing the implementation back.

**Files:**
- Review: `Tests/Support/LocalWorkbookSheetsClient.swift`
- Review: `Tests/Unit/LocalWorkbookSheetsClientTests.swift`
- Review: `Tests/Support/SheetGridFixture.swift`
- Review: `Tests/Unit/SyncCoordinatorLocalWorkbookRoundTripTests.swift`

- [ ] **Step 1: Confirm production code stayed unchanged**

Run:

```bash
git diff --name-only main...HEAD
```

Expected changed files:

```text
Tests/Support/LocalWorkbookSheetsClient.swift
Tests/Unit/LocalWorkbookSheetsClientTests.swift
Tests/Support/SheetGridFixture.swift
Tests/Unit/SyncCoordinatorLocalWorkbookRoundTripTests.swift
```

- [ ] **Step 2: Confirm no live Google or Drive scope was added**

Run:

```bash
rg -n "GoogleSheetsClient|GoogleAuth|Drive|listSpreadsheets|URLSession|USER_ENTERED|credentials|token" Tests/Support/LocalWorkbookSheetsClient.swift Tests/Unit/LocalWorkbookSheetsClientTests.swift Tests/Unit/SyncCoordinatorLocalWorkbookRoundTripTests.swift
```

Expected: no matches except the inherited `SheetsClient` protocol name if the search output includes type context from compiler diagnostics. The local workbook must not call auth, Drive, network, or Google-specific formatting behavior.

- [ ] **Step 3: Confirm no placeholders were left in new test files**

Run:

```bash
rg -n "PLACEHOLDER|REPLACE_ME|unfinished" Tests/Support/LocalWorkbookSheetsClient.swift Tests/Unit/LocalWorkbookSheetsClientTests.swift Tests/Unit/SyncCoordinatorLocalWorkbookRoundTripTests.swift
```

Expected: no matches.

- [ ] **Step 4: Confirm final git status is understandable**

Run:

```bash
git status --short
```

Expected: either clean after commits, or only unrelated pre-existing dirty files plus intentional local changes from this plan if commits were intentionally deferred.

## Out of Scope For This Plan

- Do not add live Google Sheets tests.
- Do not add Google Drive lifecycle tests.
- Do not change `SheetsClient`, `GoogleSheetsClient`, `PendingWrite`, `SheetWriter`, `SyncCoordinator`, or production persistence contracts.
- Do not simulate Google `USER_ENTERED`, formulas, locale, dates, formatted values, or quoted-range server quirks beyond A1 parsing for local tests.
- Do not reorganize the broader test suite.
- Do not replace specialized blocking, retry, or HTTP request-recorder fakes in this slice.
