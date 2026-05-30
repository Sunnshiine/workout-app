# Local Workbook Sheets Client Spec

## Goal

Create a shared local workbook `SheetsClient` test double that gives normal `swift test`
coverage a realistic read-after-write boundary for Sheet write workflows. The goal is to
test app behavior against workbook state, not only recorded API calls, while preserving the
project rule that default automated tests never touch live Google auth, live Google Sheets,
or real network connectivity.

This spec covers the main confidence layer from the Google Sheets write-testing design:
seed a realistic `SheetGrid`, run the real app write flow through `SyncCoordinator` and
`SheetWriter`, fetch the mutated grid through the same `SheetsClient` protocol, parse it
again, and assert final domain state.

## Background

The app treats the coach-managed Google Sheet as the source of truth and keeps a local-first
cache for gym reliability. The relevant constraints are documented in:

- [CONTEXT.md](../../CONTEXT.md)
- [Testing strategy](../TESTING.md)
- [ADR 0001: Google Sheet as backend with local-first sync](../adr/0001-sheet-as-backend-local-first.md)
- [ADR 0003: Fully dynamic cell targeting](../adr/0003-dynamic-cell-targeting.md)
- [ADR 0005: Legacy logs are completion evidence](../adr/0005-legacy-logs.md)
- [ADR 0006: Batched pending Sheet writes preserve local-first safety](../adr/0006-batched-pending-sheet-writes.md)

Current write-path tests verify important pieces, but most confidence is still either
planner-level or call-recorder-level. `GoogleSheetsClientTests` verifies request shape for
`values:batchUpdate`; `SheetWriterTests` and `SheetCompactLayoutTests` verify target
planning; `SyncCoordinatorBatchWriteTests` includes file-local mutating fakes; and the UI
fixture client currently treats writes as a no-op. The missing shared seam is a reusable
local workbook that behaves enough like the Sheet values boundary for fast round-trip
tests.

## Decisions

- Decision: Add a shared test-only workbook client under `Tests/Support`.
  Source: Adversarial Google Sheets testing design consensus.
  Consequence: Production `SheetsClient`, `GoogleSheetsClient`, `SheetWriter`, and
  `SyncCoordinator` contracts stay unchanged.

- Decision: The local workbook is the main confidence layer for broad Sheet write-path
  behavior.
  Source: [Testing strategy](../TESTING.md) and design consensus.
  Consequence: Normal tests can cover compact headers, continuation rows, Coach Notes,
  Legacy Logs, shifted columns, deletes, conflicts, batching, and parse-after-write
  behavior without live Google credentials.

- Decision: The local workbook preserves values literally and does not emulate
  Google-specific `USER_ENTERED` formatting.
  Source: Separation between local confidence tests and future live contract tests.
  Consequence: Google formatting, quoted-range server behavior, and live readback quirks
  remain out of scope for this spec and belong to future opt-in live tests.

- Decision: Batch update behavior is atomic at the test seam.
  Source: [ADR 0006](../adr/0006-batched-pending-sheet-writes.md).
  Consequence: If callers use `updateCells(spreadsheetId:updates:)`, tests can rely on all
  updates being visible after success and no updates being visible after failure.

- Decision: Read-after-write assertions should be preferred over recorder-only assertions
  for workflow tests.
  Source: Design consensus.
  Consequence: Tests should fetch and parse the mutated workbook state when the behavior
  under test is final Sheet state, while request-shape tests remain appropriate for
  `GoogleSheetsClient`.

## Scope

### In

- A shared `LocalWorkbookSheetsClient` test double that implements `SheetsClient`.
- Workbook state represented as tabs backed by `SheetGrid` values.
- Support for `listTabTitles`, `fetchTab`, single-range writes, and multi-range batch writes.
- A1 range parsing compatible with ranges produced by `singleCellRange(tabName:row:col:)`,
  including quoted tab names.
- Literal value persistence, including blank writes used for deletes.
- Atomic staging and commit for batch writes.
- At least one high-risk write-path round-trip test that seeds a grid, flushes pending
  writes, fetches the updated tab, parses it, and asserts domain state.
- Incremental replacement of duplicated file-local mutating fakes where the shared workbook
  provides the same behavior.

### Out

- Live Google Sheets tests.
- Google Drive file creation, cleanup, or deletion tests.
- Production read-after-write verification before pending-write deletion.
- Changes to `SheetsClient`, `GoogleSheetsClient`, `PendingWrite`, or production persistence
  shape.
- Simulation of Google `USER_ENTERED`, locale, formula, date, or formatted-value behavior.
- UI integration test rewrites.
- A broad test-suite reorganization.

## Current Architecture

`SheetsClient` is the app's boundary for Sheet I/O. It supports tab listing, Drive-backed
spreadsheet listing, tab fetches, single updates, and multi-range batch updates. The default
batch implementation throws for multiple updates unless a concrete client opts in.

`GoogleSheetsClient` is the production adapter. It fetches tab values with
`valueRenderOption=FORMATTED_VALUE&majorDimension=ROWS` and writes with
`values:batchUpdate`, `valueInputOption=USER_ENTERED`, and `majorDimension=ROWS`.

`SheetWritePlanner` resolves semantic pending writes into transient cell updates by reading
a current `SheetGrid` snapshot and applying dynamic layout rules from the Sheet layout
interpreter. `SheetWriter` converts planned updates into A1 ranges and calls `SheetsClient`.

`SyncCoordinator` owns pending-write flush orchestration. It fetches one grid snapshot per
Block tab, plans pending writes in order, batches non-overlapping updates, writes through
`SheetWriter`, and deletes included pending writes after the batch succeeds.

Current test doubles are uneven. Some only record calls, some mutate local grids inside a
single test file, and the UI fixture write path is intentionally inert. That makes it easy
for workflow tests to assert planned writes without proving the app can read its own final
Sheet state.

## Target Architecture

`LocalWorkbookSheetsClient` becomes the shared test-only `SheetsClient` implementation for
write-path workflow tests. Tests seed it with one or more tabs, pass it into existing app
objects, then assert behavior through protocol reads rather than internal fake state.

The local workbook owns only test state. It does not become a production abstraction and
does not change the production client. It should be safe for async tests by isolating
workbook state and recorded batches behind a concurrency-safe boundary.

The preferred workflow shape is:

1. Seed a workbook tab with a realistic `SheetGrid`.
2. Insert semantic `PendingWrite` records into an in-memory SwiftData context.
3. Run `SyncCoordinator.flushPending(spreadsheetId:)`.
4. Fetch the tab through `LocalWorkbookSheetsClient.fetchTab`.
5. Parse the fetched grid with `SheetParser`.
6. Assert final domain state, protected Coach Notes, Set Logs, Last Set RPE, conflicts, and
   pending-write deletion or retry behavior as appropriate.

Recorder-style tests remain useful only when the behavior under test is the exact outbound
request shape. `GoogleSheetsClientTests` should continue to assert HTTP method, endpoint,
authorization, request body, and value input option with a request recorder.

## Contracts

### [ADDED] `LocalWorkbookSheetsClient`

Test-only `SheetsClient` implementation backed by local workbook state.

```swift
actor LocalWorkbookSheetsClient: SheetsClient {
    init(spreadsheetId: String = "sid", tabs: [String: SheetGrid])

    func listTabTitles(spreadsheetId: String) async throws -> [String]
    func fetchTab(spreadsheetId: String, tabName: String) async throws -> SheetGrid
    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws
    func updateCells(spreadsheetId: String, updates: [SheetValueRangeUpdate]) async throws
}
```

The exact helper initializer and inspection methods may change during implementation, but
the stable contract is that tests interact with app code through `SheetsClient`, not through
production-only APIs or direct `SyncCoordinator` internals.

### [ADDED] Local Workbook State Contract

The workbook stores tab titles mapped to `SheetGrid` values. `fetchTab` returns the current
grid snapshot for the requested tab. Writes must update workbook state so later reads see
the new values.

The workbook may grow rows or columns when a valid update targets a cell outside the seeded
grid bounds. This matches existing planner test behavior and keeps fixtures focused on
meaningful cells instead of padding.

### [ADDED] A1 Range Contract

The workbook accepts A1 ranges generated by production helpers, including quoted tab names:

```swift
"'Block 27'!K15"
"'Coach''s Block'!I20"
```

The initial contract must support single-cell ranges because `SheetWriter` writes each
planned `SheetCellUpdate` as a one-cell value range. It may support rectangular ranges if
that keeps the range parser simpler and more faithful to the Google values API, but broad
range coverage is not required before the first workflow tests.

Malformed ranges or unknown tab names must throw before mutating workbook state.

### [ADDED] Batch Atomicity Contract

`updateCells(spreadsheetId:updates:)` stages every range update against copied workbook
state. It commits only after every update is valid. If any update is malformed, targets an
unknown tab, or has unsupported dimensions, the method throws and the workbook remains
unchanged.

This keeps tests aligned with [ADR 0006](../adr/0006-batched-pending-sheet-writes.md), where
the app treats a successful batch as the pending-write deletion boundary and a failed batch
as retryable without partial local deletion.

### [ADDED] Literal Value Contract

The workbook preserves string values exactly as provided by the app. It must not parse
formulas, coerce numbers, localize dates, trim values, or emulate `USER_ENTERED`.

An empty string written to a cell is persisted as an empty string and represents the local
equivalent of clearing that cell for delete-write tests.

### [ADDED] Recorded Batch Inspection Contract

Tests may inspect recorded write batches when the ordering or grouping behavior is itself
the assertion. Recorded batches are secondary evidence; workflow tests should prefer
fetch-and-parse assertions for final state.

### [CHANGED] Write-Path Test Style

High-risk write-path tests should move from call-recorder-only confidence toward
workbook-state confidence. The minimum expected assertion path is:

- pending writes are flushed through `SyncCoordinator`;
- the workbook reflects the expected Notes and Last Set RPE cells;
- parsing the fetched workbook yields the expected `Set` states;
- pending writes are deleted only after successful workbook writes, or retained on failure.

### [REMOVED] Duplicated Generic Workbook Mutation Helpers

After the shared workbook covers equivalent behavior, generic file-local helpers that parse
A1 references and mutate `SheetGrid` state should be removed from tests that no longer need
specialized behavior. Specialized blocking or failure-injection clients may remain where
they test concurrency or retry paths that the shared workbook does not own.

## Migration Plan

### Phase 1: Shared Workbook Contract

- Change: Add `LocalWorkbookSheetsClient` under `Tests/Support` with unit coverage for tab
  fetches, single-cell writes, batch writes, blank writes, quoted tab names, grid growth,
  and failed-batch no-partial-commit behavior.
- Compatibility: Production code remains unchanged. Existing tests may continue using their
  current stubs during this phase.
- Acceptance criteria: The workbook helper passes focused tests and does not require live
  Google credentials or network access.

### Phase 2: First End-to-End Write-Path Round Trip

- Change: Add one high-risk round-trip test using the shared workbook: seed a Coach Note or
  AMRAP header Notes layout, insert Set Log plus paired Last Set RPE pending writes, flush
  through `SyncCoordinator`, fetch the updated tab, parse it, and assert protected Coach Note,
  continuation Set Logs, Last Set RPE, and pending-write deletion.
- Compatibility: Existing planner and batch tests remain available as narrower regression
  tests.
- Acceptance criteria: The test proves final workbook state and parsed domain state, not
  only planned A1 ranges.

### Phase 3: Incremental Adoption

- Change: Replace duplicated generic mutating stubs in write-path tests with the shared
  workbook where doing so reduces fixture drift and preserves focused failure behavior.
- Compatibility: Request-recorder tests and specialized concurrency/failure-injection tests
  remain separate when recorder or blocking behavior is the point of the test.
- Acceptance criteria: The common seed-write-fetch-parse pattern is reusable from
  `Tests/Support`, and no test loses coverage for batching, retry, conflict, or ordering
  behavior.

## Deletion Criteria

- Remove file-local generic A1 parsing and `SheetGrid` mutation helpers once the shared
  workbook provides the same behavior for those tests.
- Keep specialized fake clients when they model behavior outside the shared workbook's
  ownership, such as blocked async updates, forced network failures, or exact HTTP request
  recording.
- Do not remove `GoogleSheetsClientTests`; they cover production request shape, which the
  local workbook intentionally does not model.

## Acceptance Criteria

- [ ] A shared test-only `LocalWorkbookSheetsClient` implements the `SheetsClient` read and
      write contract without live Google auth, live Google Sheets, or real network access.
- [ ] Batch writes are atomic in the local workbook: a failed multi-update batch leaves all
      workbook tabs unchanged.
- [ ] Blank writes, quoted tab names, dynamically grown rows or columns, and read-after-write
      fetches are covered by focused tests.
- [ ] At least one high-risk write workflow runs through `SyncCoordinator.flushPending`,
      fetches the mutated workbook, reparses it with `SheetParser`, and asserts final domain
      state.
- [ ] Existing request-shape tests for `GoogleSheetsClient` remain responsible for
      `USER_ENTERED`, endpoint, authorization, and JSON body assertions.

## Testing Strategy

Use Swift Testing for new tests. The narrow verification gate for this spec is
`swift test --filter LocalWorkbookSheetsClientTests` plus the first round-trip test's filter.
Before merging implementation, also run `swift test --filter SyncCoordinatorBatchWriteTests`
and the repo's standard `swift test` gate. If implementation touches Swift files, run
`swiftlint lint --quiet` when available.

The local workbook tests should include both happy-path and failure-path coverage. Failure
coverage must prove no partial batch commit, because that is the key behavior required by
the app's pending-write deletion model.

## Open Questions

- None. Live Google Sheets contract tests and Google Drive lifecycle tests are intentionally
  future enhancements outside this spec.
