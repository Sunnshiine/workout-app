# Exercise history: what the local cache can actually serve (audit)

Wayfinder ticket #339 · 2026-07-11 · Research audit, code as of this date.
Scope: inventory of facts and trade-offs for a future Performance History feature.
**This document records findings only; the decision is a separate ticket.**

Terminology follows `CONTEXT.md`: Performance History, Last Performed, Legacy Log,
Set Log, Block, Week, Session, Cadence.

---

## 1. What is on device today, and what is discarded

### 1.1 Persistence layer

- Everything durable lives in one SwiftData `ModelContainer` holding four models:
  `Block`, `PendingWrite`, `WriteTargetAuditEntry`, `LastPerformedEntry`
  (`WorkoutTracker/WorkoutTrackerApp.swift:46`). Default SwiftData configuration —
  a SQLite `default.store` in the app's Application Support container; no custom
  `ModelConfiguration` in the production path (UI-test fixtures use an in-memory
  container, `WorkoutTracker/Fixtures/UITestFixture.swift:88-91`).
- `UserDefaults` holds only the Current Session manual-override key
  `advancedToOrderV2_<tabName>` (`WorkoutTracker/Stores/WorkoutStore.swift:269-275`)
  plus settings. No history data lives in UserDefaults or in files.

### 1.2 Cached Blocks: exactly one — the current Block

- On every sync, `SyncCoordinator.sync` lists tab titles, picks the single
  current Block tab — the highest-numbered `Block N` title
  (`currentBlockTab(from:)`, `WorkoutTracker/Parsing/BlockTabSelector.swift:3-14`) —
  and fetches only that tab (`WorkoutTracker/Stores/SyncCoordinator.swift:109-121`).
- `replacePersistedBlock` then **deletes every persisted `Block`** and inserts the
  freshly parsed one (`SyncCoordinator.swift:147-154`; the discard is the loop at
  line 151: `for existing in try context.fetch(FetchDescriptor<Block>()) { context.delete(existing) }`).
  Historical Blocks are therefore never cached, and even the previous copy of the
  current Block is replaced wholesale (with pending-write overlay and local
  `loggedAt` preservation, lines 148-150, 156-182, 298-343).
- `WorkoutStore.reload` assumes this single-Block invariant:
  `block = try? context.fetch(FetchDescriptor<Block>()).first`
  (`WorkoutTracker/Stores/WorkoutStore.swift:105`).

### 1.3 The `last_performed` index: one entry per exercise full name

- Model: `LastPerformedEntry` (`WorkoutTracker/Models/LastPerformedEntry.swift`),
  with `@Attribute(.unique) var fullName` (line 6). Fields: `fullName`, `baseName`,
  `result: SetLog?` (structured, only when the performance was exactly one
  structured Set Log), `resultText: String?` (the display string — a joined
  comma list of Set Logs, or a raw Legacy Log), `performedOn: Date`,
  `source: String` (e.g. `"Block 27 · W2 D3"`, format at
  `WorkoutTracker/Progress/LastPerformedExtractor.swift:51`).
- The uniqueness is enforced twice over:
  1. **Within a Block**: `LastPerformedExtractor.records(from:)` collapses to the
     latest evidence-bearing Session per `fullName`
     (`LastPerformedExtractor.swift:37, 54-60`).
  2. **Across ingests**: `LastPerformedIndex.ingest` fetches any existing entry by
     `fullName` and **overwrites its fields in place** when the incoming
     `performedOn >=` the existing one; older data is lost, never appended
     (`WorkoutTracker/Progress/LastPerformedIndex.swift:32-47`).
- `performedOn` comes from the Session date parsed off the Week's date row
  (`WorkoutTracker/Parsing/SheetParser.swift:410-412`), falling back to
  `.distantPast` when absent (`LastPerformedExtractor.swift:44`). Entries with
  unparseable dates therefore sort/dedupe degenerately on `.distantPast`.

### 1.4 Index lifecycle: when it is written

Three writers, all funneling through `LastPerformedIndex.ingest`:

1. **Every sync, from the current Block parse** —
   `SyncCoordinator.sync` extracts and ingests after replacing the Block
   (`SyncCoordinator.swift:122-126`).
2. **Backfill from historical tabs** — after each sync,
   `launchLastPerformedBackfill` walks `sortedHistoricalTabs` (all other
   `Block N` tabs, newest first, `BlockTabSelector.swift:16-23`) in a background
   `Task`, fetching one tab snapshot at a time, parsing it, extracting records,
   and ingesting (`SyncCoordinator.swift:197-254`, per-tab fetch+parse in
   `historicalLastPerformedRecords`, lines 256-264). Two early-stop rules make
   this *lazy, not exhaustive*:
   - The whole backfill is skipped when every unique Exercise in the current
     Block already has a lookup hit (`hasLastPerformedCoverage` guard,
     `SyncCoordinator.swift:224`).
   - The tab loop returns as soon as coverage is achieved (line 250-252).
   - A tab that fails to fetch/parse is silently skipped (`catch { continue }`,
     lines 237-239).
   This matches ADR-0002's intent: "typically 1–2 Blocks back"
   (`docs/adr/0002-last-performed-local-index.md:7`). Consequence: the index
   usually contains entries only from the current Block plus however few
   historical tabs were needed once — most of the ~27 tabs are never read.
3. **Live logging** — every `WorkoutStore.log` ingests the just-logged Set as
   that Exercise's new Last Performed entry
   (`WorkoutStore.swift:236-252`, called at line 336).

Read path: `LastPerformedLookupStore.refresh()` snapshots the whole table into an
in-memory `LastPerformedLookupSnapshot`
(`WorkoutTracker/Stores/LastPerformedLookupStore.swift:25-27`,
`WorkoutTracker/Progress/LastPerformedIndex.swift:27-30`), consumed by
`SessionView` / `SessionStageView`
(`WorkoutTracker/Views/SessionStageView.swift:27,40`).

`LastPerformedBackfillObserving` (`WorkoutTracker/Stores/LastPerformedBackfillObserver.swift`)
is a completion-signal seam only; production assembly injects nothing
(`WorkoutTrackerApp.swift:57-63` passes no observer, so the
`NoopLastPerformedBackfillObserver` default at `SyncCoordinator.swift:34` is used;
the only real conformer is a test probe, `Tests/Unit/SyncCoordinatorTests.swift:93`).

### 1.5 What is discarded, precisely

| Data | Where discarded |
|---|---|
| All non-current Blocks (prescriptions, per-Set Logs, Coach Notes) | never persisted; only current tab fetched (`SyncCoordinator.swift:111-121`) |
| Previous copy of the current Block | deleted on each sync (`SyncCoordinator.swift:151`) |
| All but the latest performance per `fullName` within a Block | `LastPerformedExtractor.swift:54-60` |
| Older `LastPerformedEntry` data on newer ingest | overwritten in place, `LastPerformedIndex.swift:35-41` |
| Parsed historical `ParsedBlockModel`s from backfill | transient in the detached task; only extracted records survive (`SyncCoordinator.swift:256-264`) |
| Most historical tabs entirely | coverage-based early stop (`SyncCoordinator.swift:224, 250`) |
| Skipped/Pending Sets and Unstructured Set Logs as evidence | evidence = structured `.logged` Set Logs, else Legacy Log; an Unstructured Set Log has no `setLog` so it contributes completion but no Last Performed result (`LastPerformedExtractor.swift:79-92`) |

Other persisted models are not history: `PendingWrite` rows are deleted after a
successful batch flush (`SyncCoordinator.swift:611-620`; semantics per
`docs/adr/0006-batched-pending-sheet-writes.md`), and `WriteTargetAuditEntry` is
a pruned diagnostic ring buffer (`SyncCoordinator.swift:694-703`).

**Bottom line:** the only exercise history on device is one
`LastPerformedEntry` per exercise full name — a display string, an optional
single structured `SetLog`, a date, and a source label. There is no second-most-recent
performance anywhere on device.

### 1.6 What the Sheets client can fetch

`SheetsClient` protocol (`WorkoutTracker/Sheets/SheetsClient.swift:8-15`):

- `listTabTitles(spreadsheetId:)` — 1 GET, titles only
  (`WorkoutTracker/Sheets/GoogleSheetsClient.swift:95-105`).
- `fetchTabSnapshot(spreadsheetId:tabName:)` — **one tab per GET**, via
  `GET /v4/spreadsheets/{id}?includeGridData=true&ranges=<tab>` with a fields
  mask limiting payload to `formattedValue` + row visibility
  (`GoogleSheetsClient.swift:133-149`). There is no multi-range/batch **read**
  in the client (the API endpoint accepts repeated `ranges` params, but the
  client sends exactly one — adding batch reads would be a client change, not a
  protocol impossibility).
- Writes *are* batched (`values:batchUpdate`, `GoogleSheetsClient.swift:158-182`).
- `listSpreadsheets` — Drive file listing for the sheet picker (lines 107-131).
- **No rate/quota/backoff handling anywhere**: non-2xx becomes
  `SheetsError.http(status)` (`GoogleSheetsClient.swift:184-190`); the backfill
  loop just skips a failed tab (`SyncCoordinator.swift:237-239`). (External
  fact, not in-repo: Google Sheets API read quota is per-minute, ~60
  reads/min/user by default — a sequential 27-tab sweep fits inside one minute's
  quota but is a burst with no retry protection in this codebase.)

---

## 2. Options for multi-performance history

### Option A — Append-only history index via the existing backfill path

Extend `LastPerformedExtractor` to emit *every* evidence-bearing
(exercise, Session) performance instead of collapsing per `fullName`
(remove the `latestByExercise` reduction, `LastPerformedExtractor.swift:37-63`),
store them in a new/changed model without the `@Attribute(.unique) fullName`
constraint (`LastPerformedEntry.swift:6`), and make `ingest` insert-if-absent
keyed on (`fullName`, `source`) rather than overwrite
(`LastPerformedIndex.swift:32-47`). The existing dedupe key cannot be
(`fullName`, `performedOn`) alone: `performedOn` collapses to `.distantPast`
when the Sheet date fails to parse (`LastPerformedExtractor.swift:44`); `source`
(tab·week·day) is the stable identifier.

- **Sync cost:** the fetch machinery is unchanged, but the coverage-based early
  stops (`SyncCoordinator.swift:224, 250`) are wrong for history — they stop
  after 1–2 tabs. Full depth means up to ~27 sequential `fetchTabSnapshot`
  GETs, **once** (the scan is resumable per-tab since each tab ingests
  independently). Steady state after that: zero extra calls — new performances
  arrive from the current-tab sync (`SyncCoordinator.swift:122-126`) and from
  live logging (`WorkoutStore.swift:236-252`). Coach edits to *old* tabs are
  not observed unless a re-scan policy is added.
- **Storage shape:** one row per performance. Rough envelope: 27 Blocks × 8–24
  Sessions × ~5–8 Exercises ≈ 1,000–5,000 rows; each row is a few short strings
  plus a date (~150–300 bytes) → well under 1 MB in SQLite. The in-memory
  `LastPerformedLookupSnapshot` (`LastPerformedLookup.swift`) keeps only the
  latest per name, so Last Performed display cost is unchanged; history reads
  can be on-demand `FetchDescriptor` queries.
- **Offline:** full history available mid-Session with no network once the
  one-time deepened backfill has run — same offline profile as today's index.

### Option B — On-demand backwards Sheet scan when the athlete opens history

Reuse `sortedHistoricalTabs` + the per-tab fetch/parse/extract pipeline that
already exists as `SyncCoordinator.historicalLastPerformedRecords`
(`SyncCoordinator.swift:256-264`), triggered from a history screen instead of
sync, filtering records to one exercise name.

- **Sync cost:** N GETs *at tap time*, sequential, each pulling a full tab grid
  (`includeGridData=true`); a deep scan (rare exercise) approaches 27 calls.
  This is the exact approach ADR-0002 rejected for Last Performed: "scanning
  backwards through Sheet tabs on demand — is too slow and requires network
  access at the moment of display"
  (`docs/adr/0002-last-performed-local-index.md:3`). There is no partial-tab
  read (the layout interpreter needs the whole grid to find Sessions), no
  caching layer, and no backoff, so repeated opens repeat the sweep unless
  results are memoized.
- **Storage shape:** none required (cheapest); optionally cache scan results,
  which converges on Option A with lazier population.
- **Offline:** nothing. The athlete's context is "mid-Session, on the gym
  floor" with reliable-but-not-guaranteed connectivity (`PRODUCT.md:9`,
  `docs/adr/0001-sheet-as-backend-local-first.md:3`); pure on-demand fetch
  serves no history when the network is down.

### Option C — Full-history fetch across the ~27 Block tabs (one-time or periodic)

Hook a full sweep into the existing post-sync hand-off:
`SyncCoordinator.sync` already ends by calling `launchLastPerformedBackfill`
with `spreadsheetId`, all `titles`, and the current tab
(`SyncCoordinator.swift:133-138`); a history variant is the same loop without
the two coverage early-stops, reusing `historicalLastPerformedRecords` and the
`LastPerformedBackfillObserving` seam for completion signaling.

- **Sync cost:** ~27 sequential `fetchTabSnapshot` GETs (each a formattedValue-
  masked full grid; modest tens-of-KB payloads) plus the `listTabTitles` call
  already made by sync. One-time cost is identical to Option A's first run —
  the difference is *policy*: periodic re-sweeps (to catch coach edits to old
  tabs) multiply the cost by the refresh frequency and hit the no-backoff
  client each time. ADR-0002 explicitly rejected "Fetch all 27 Blocks on first
  launch" as "unnecessary data transfer" *for Last Performed*
  (`docs/adr/0002:9`); Performance History has a different requirement
  (multiple entries per Exercise), so that rejection's premise — "a reference
  that rarely goes back more than 1–2 Blocks" — does not automatically carry
  over. That tension is the trade-off to resolve in the decision ticket.
- **Storage shape:** whatever the sweep retains — extracted per-performance
  records (same shape/size as Option A), or raw parsed blocks (see Option D).
- **Offline:** full history offline after the first complete sweep; staleness
  bounded by the re-sweep period for old-tab edits.

### Option D — Persist old Blocks themselves (serve history from cached Blocks)

Not possible from today's cache: only one `Block` survives sync
(`SyncCoordinator.swift:151`). The variant is to stop deleting non-current
Blocks and persist one `Block` graph per tab (the backfill already *parses*
full historical `ParsedBlockModel`s and throws them away,
`SyncCoordinator.swift:256-264` — persistence would capture what is currently
transient).

- **Sync cost:** identical fetch profile to Options A/C (the tabs must be
  fetched either way).
- **Storage shape:** far larger — full prescription data, per-Set rows, Coach
  Notes, per-Set states for every Session of every Block (a `Block` graph is
  `Block → Week → Session → Exercise → ExerciseSet`,
  `WorkoutTracker/Models/`). Still likely tens of MB at worst, but it persists
  much data history never displays.
- **Code impact (largest of the four):** the single-Block invariant is baked
  in — `WorkoutStore.reload` takes `.first` of all Blocks
  (`WorkoutStore.swift:105`), `hasPriorAppState` counts any Block
  (`WorkoutTrackerApp.swift:68-70`), `replacePersistedBlock`/pending-write
  overlay assume the fetched set is "the" block
  (`SyncCoordinator.swift:147-182`). All would need tab-scoped fetches.
- **Benefit unique to this option:** full-fidelity history — true per-Set
  structured logs and prescriptions, enabling richer Performance History UI
  than the flattened result strings of A–C.
- **Offline:** full history offline once cached, same as A/C.

---

## 3. Interaction with existing mechanisms

### 3.1 Two-tier name lookup (full name incl. Cadence → base name)

- The Cadence split is `splitCadence` (`WorkoutTracker/Parsing/SheetParser.swift:6-12`);
  every parsed Exercise carries both `name` (full, incl. Cadence) and `baseName`
  (`SheetParser.swift:214-220`, persisted on `Exercise`,
  `WorkoutTracker/Models/Exercise.swift:10-11`).
- The two-tier lookup exists in two parallel forms, both keyed on those two
  fields:
  1. Persisted query: `LastPerformedIndex.lookup` — exact `fullName` predicate
     first, then `baseName` predicate sorted `performedOn` descending, `.first`
     (`LastPerformedIndex.swift:12-25`).
  2. In-memory snapshot: `LastPerformedLookupSnapshot.lookup` —
     `exactMatches[fullName] ?? fallbackMatches[baseName]` dictionaries
     (`LastPerformedLookup.swift:23-51`).
- Implication per option: every history entry must persist **both** `fullName`
  and `baseName` (the extractor already produces both,
  `LastPerformedExtractor.swift:46-47`), so:
  - **A/C:** the history query is the same two-tier shape minus `.first` —
    fetch by `fullName`, and if empty fetch by `baseName` sorted by
    `performedOn` descending. Alternatively key the history *list* by
    `baseName` and retain `fullName` per row so the UI can group or label
    Cadence variants ("2-3:1:0 BB RDL" vs "BB RDL") instead of silently mixing
    them.
  - **B:** the scan filter must apply the same two-tier match per tab
    (exact-name pass, then base-name pass) or it will miss history recorded
    under a different Cadence prefix.
  - **D:** lookup would traverse persisted Block graphs matching
    `Exercise.name` then `Exercise.baseName` — same keys, new query path.

### 3.2 Legacy Logs as completion evidence

- Today: `LastPerformedExtractor.lastPerformedEvidence` prefers structured
  `.logged` Set Logs (joined into `resultText`, with a structured `result`
  only when there is exactly one log); when none exist it falls back to the
  **raw** `exercise.legacyLog` string with `result = nil`
  (`LastPerformedExtractor.swift:79-92`). Display uses
  `LastPerformedEntry.displayResultText` (`LastPerformedEntry.swift:13-15`),
  i.e. Legacy Logs are surfaced verbatim — exactly as `CONTEXT.md` requires
  ("history display the raw entered text", Legacy Log entry, `CONTEXT.md:49`;
  Last Performed entry, `CONTEXT.md:61`) and as ADR-0005 mandates ("must not
  automatically migrate ... or inventing structured per-set data",
  `docs/adr/0005-legacy-logs.md:3-5`).
- Implication for all options: older Blocks are precisely where Legacy Logs
  dominate, so a multi-performance history will be **substantially raw-text
  entries without per-Set structure** (`result: SetLog?` nil, no reliable
  weight/reps/RPE fields). Any Performance History UI or trend computation can
  only rely on structured data opportunistically; the storage shape must keep
  the raw `resultText` as the canonical record (Options A–C inherit this
  automatically from the extractor; Option D would surface `Exercise.legacyLog`
  directly).
- Adjacent fact: an Unstructured Set Log (Set-level free text,
  `CONTEXT.md:41`) marks a Set `.logged` but has no `setLog`, so it produces
  no evidence text in the extractor — an Exercise completed only via
  Unstructured Set Logs and lacking a Legacy Log yields **no** Last Performed
  record today (`LastPerformedExtractor.swift:80-91`). A history feature
  inherits that gap unless the evidence function is extended.
- Skipped occurrences: Skipped Sets carry no `setLog`, so a fully skipped
  performance yields no candidate and the extractor naturally "continues
  backwards" to the previous evidence-bearing Session — the ADR-0002 /
  `CONTEXT.md:61` skip rule is implemented implicitly by the evidence filter.

---

## 4. Comparison table

| | A. Append-only index via backfill | B. On-demand backwards scan | C. Full-history sweep in sync | D. Persist old Blocks |
|---|---|---|---|---|
| API calls (first fill) | up to ~27 tab GETs, once, resumable | 1–27 GETs *per history open* (until memoized) | ~27 tab GETs once (+ per refresh period) | same as A/C |
| API calls (steady state) | 0 (fed by sync + live logging) | repeats on demand | 0 if one-time; N per re-sweep | 0 if one-time |
| Sees coach edits to old tabs | no (without re-scan policy) | yes (always fresh) | yes iff periodic | yes iff re-fetched |
| Storage | ~1–5k small rows, ≲1 MB | none (or optional cache) | same as A | full Block graphs, largest |
| Offline mid-Session | full history | **none** | full history | full history |
| Latency at display | instant (local query) | seconds, network-bound | instant | instant |
| Structured per-Set data | flattened `resultText` (+ single `SetLog` when 1 log) | same (transient) | same as A | full `ExerciseSet` fidelity |
| Legacy Logs | raw text, preserved as today | raw text | raw text | raw `Exercise.legacyLog` |
| Two-tier lookup fit | same keys, drop `.first` | must re-implement match in scan | same as A | new query over Block graphs |
| Main code touch points | `LastPerformedExtractor`, `LastPerformedEntry` uniqueness, `ingest`, backfill early-stops (`SyncCoordinator.swift:224,250`) | new history service reusing `historicalLastPerformedRecords` | `launchLastPerformedBackfill` sibling + observer seam | single-Block invariant (`WorkoutStore.swift:105`, `SyncCoordinator.swift:147-182`, `WorkoutTrackerApp.swift:68-70`) |
| Doc tension | none | contradicts ADR-0002's stated rationale | revisits ADR-0002's rejected alternative (different requirement) | extends ADR-0001's "cache of the current Block" scope |
