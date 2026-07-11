# Performance History: does it need new architecture, or does the local cache extension suffice?

Wayfinder ticket #350 · 2026-07-11 · Research inventory, code as of this date.
Builds on the ticket #339 audit
(`docs/research/2026-07-11-exercise-history-cache-audit.md`, currently on branch
`claude/wayfinder-workout-app-uzso94`) — facts established there are referenced,
not repeated. **This document records facts and trade-offs only; the decision is
a separate ticket.**

Terminology follows `CONTEXT.md`: Performance History (`CONTEXT.md:63`),
Last Performed (`CONTEXT.md:61`), Legacy Log (`CONTEXT.md:49`), Set Log
(`CONTEXT.md:39`).

---

## Summary (answer-first)

The facts do not surface any load that a CloudKit tier would relieve. Every
byte a Performance History store would hold is *derived* from Sheet tabs the
coach keeps forever — a CloudKit container would be a third copy of data the
Sheet (copy 1) and the on-device SwiftData store (copy 2) already hold, and
ADR-0001 states "The app never independently owns data"
(`docs/adr/0001-sheet-as-backend-local-first.md:5`). What CloudKit would
genuinely add is multi-device sync and off-device backup *of the derived
index* — but the derived index is fully re-derivable from the Sheet by the
existing backfill machinery, so the backup value is "skip a ~29-request
re-fill," not "prevent data loss." Adopting it would cost: entitlements and a
paid-developer-account container, a schema rework (both `@Attribute(.unique)`
constraints in the repo are CloudKit-incompatible per Apple's docs), an
additive-only production schema commitment, an iCloud-account dependency, and
a new eventual-consistency/conflict dimension that ADR-0001 explicitly built
the app to avoid. At the audited scale (~1–5k rows, ≲1 MB) the on-device store
is nowhere near any SQLite/SwiftData limit — the app already fetches the
*entire* index table into memory on every refresh without ceremony.

Independent of the storage choice, the initial ~27-tab fill runs on-device
either way. The existing backfill pattern already provides sequential
one-tab-at-a-time fetching with off-main-actor parsing at `.background`
priority, and per-tab persistence that survives app kill. What it does *not*
provide — verified — is any rate-limit handling (no 429 detection, no
backoff, no retry; a failed tab is silently skipped) and any resumability
cursor (a restarted full fill would re-fetch all tabs unless per-tab
completion is recorded). A single sweep (~29 read requests) fits inside
Google's official 60-reads/min/user quota, but with zero headroom management
and silent gaps on failure.

---

## 1. What CloudKit would actually buy here

### 1.1 What it buys, honestly

- **Multi-device sync** of the derived history index, via CloudKit's private
  database ("a specific record zone in the CloudKit private database, which is
  accessible only to the current user" —
  [Mirroring a Core Data store with CloudKit](https://developer.apple.com/documentation/coredata/mirroring-a-core-data-store-with-cloudkit)).
  A second device would receive the filled index without re-running the
  ~27-tab sweep. Today the app is a single-device, single-athlete client; no
  requirement in `PRODUCT.md`/`CONTEXT.md` names a second device.
- **Off-device durability** of the index. But durability of the *underlying
  data* already exists twice: the Sheet holds every historical tab (the coach
  edits it directly and never hands ownership to the app, ADR-0001), and the
  device SQLite store holds the extracted rows. Losing the device loses only
  the derived rows, which the existing backfill path
  (`WorkoutTracker/Stores/SyncCoordinator.swift:197-264`) reconstructs from
  the Sheet. The only device-local data *not* re-derivable from the Sheet are
  local `loggedAt` timestamps (`SyncCoordinator.swift:298-343`) and unflushed
  `PendingWrite` rows — neither of which is Performance History, and neither
  of which a history-only CloudKit config would cover.
- **A second durable store** in the literal sense — but SwiftData's CloudKit
  integration *mirrors* the same local store to iCloud; it does not offload
  storage from the device. Device-side footprint is unchanged or larger.

### 1.2 What adopting it would require of this codebase

- **Container setup.** The production container is a single bare
  `ModelContainer(for: Block.self, PendingWrite.self, WriteTargetAuditEntry.self, LastPerformedEntry.self)`
  with no `ModelConfiguration` at all
  (`WorkoutTracker/WorkoutTrackerApp.swift:46`). CloudKit adoption means
  introducing explicit configurations — e.g.
  `ModelConfiguration(cloudKitDatabase: .private("iCloud.…"))` for the synced
  models and `.none` for the rest ("Specifying `none` overrides any
  automatically discovered identifiers and disables SwiftData's automatic
  iCloud sync" —
  [Syncing model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)).
  By default "SwiftData inspects your app's `Entitlements.plist` file to
  determine which CloudKit container to use, and selects the first identifier
  it finds" (same page) — so a sloppy adoption would try to sync *everything*.
- **Splitting the store.** Syncing only a history model while keeping
  `Block`/`PendingWrite` local means separate configurations, and Apple's
  CloudKit model rules state "Entities in a configuration must not have
  relationships to entities in another configuration"
  ([Creating a Core Data model for CloudKit](https://developer.apple.com/documentation/CoreData/creating-a-core-data-model-for-cloudkit)).
  A standalone history model (no relationships to `Block`) satisfies this; any
  design that relates history rows to the persisted `Block` graph does not.
- **Entitlements & capabilities.** Two are mandatory per Apple: the iCloud
  capability with CloudKit enabled plus a container ("an active Apple
  Developer account with admin permissions" is required), and the Background
  Modes capability with Remote notifications ("The system delivers remote
  notifications silently to your app, allowing SwiftData to process the
  changes … and keep your local model data in sync") — both from
  [Syncing model data across a person's devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices).
  Note the repo's `Secrets.xcconfig` bootstrap complexity exists precisely
  because app-target entitlements/config are already a friction point
  (`CLAUDE.md`, Git Worktrees section); this adds another axis.
- **Schema rules (Apple-documented).** CloudKit-synced SwiftData models must
  drop unique constraints — "The framework synchronizes changes concurrently
  and at opportune times, which means CloudKit is unable to enforce the
  `unique` property option"; all relationships must be optional — "The iCloud
  servers don't guarantee atomic processing of relationship changes, so
  CloudKit requires all relationships to be optional"; and the `deny` delete
  rule is unsupported (all from the SwiftData syncing page above; the Core
  Data model page adds "Unique constraints aren't supported" and "All
  relationships must have an inverse"). Concretely in this repo:
  - `LastPerformedEntry.fullName` is `@Attribute(.unique)`
    (`WorkoutTracker/Models/LastPerformedEntry.swift:6`) — incompatible as-is.
    (The #339 audit's Option A removes this uniqueness anyway, so this is a
    shared prerequisite, not CloudKit-only — but under CloudKit the app could
    *never* rely on store-level uniqueness for dedupe; app-level dedupe on
    (`fullName`, `source`) becomes mandatory rather than chosen.)
  - `Block.tabName` is also `@Attribute(.unique)`
    (`WorkoutTracker/Models/Block.swift:6`) — a second blocker if the whole
    container were synced rather than a split configuration.
- **Schema lifecycle.** The CloudKit schema must be manually initialized in
  development and promoted before release, and "CloudKit schemas are additive
  only, which means you're unable to delete model types or change existing
  model attributes after you promote a schema to production" (SwiftData
  syncing page). Today the app has no such one-way door: schema changes are a
  local migration at worst.

---

## 2. What it would cost

Measured against the standing simplicity preference and today's path — the
entire persistence setup is one line (`WorkoutTrackerApp.swift:46`) and the
entire write path is `context.insert`/`context.save` on the main context.

| Dimension | Today (SwiftData-only) | With CloudKit |
|---|---|---|
| Setup | one `ModelContainer(for:)` line (`WorkoutTrackerApp.swift:46`) | container split into explicit `ModelConfiguration`s, iCloud + CloudKit container entitlement, Background Modes/remote notifications, dev-schema init + production promotion ([Apple](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)) |
| Account dependency | none beyond Google Sign-In (already required for the Sheet, `WorkoutTracker/Sheets/GoogleAuth.swift`) | adds a *second* account dependency: "You also need an iCloud account to save records to a CloudKit container" ([Apple](https://developer.apple.com/documentation/coredata/mirroring-a-core-data-store-with-cloudkit)); signed-out users get local-only behavior with a dormant sync layer |
| Conflict handling | none needed for the index: single device, single writer path, `ingest` is deterministic overwrite-if-newer (`WorkoutTracker/Progress/LastPerformedIndex.swift:32-47`); ADR-0001 chose the Sheet write protocol precisely to work "without requiring conflict-resolution infrastructure" (`docs/adr/0001:7`) | CloudKit merges arrive concurrently and out of order (Apple's stated reason for banning `unique` and requiring optional relationships); two devices independently deriving rows from the Sheet can insert duplicates the store cannot reject — reconciliation logic (dedupe keys, latest-wins rules) moves into app code and must tolerate eventual consistency |
| Offline semantics | deterministic: everything readable/writable offline, one store, sync to the Sheet is the only network edge | unchanged for reads/writes (local mirror), but adds a background sync machine (silent pushes, retry states) whose failures are a new class of "why is my other device stale" |
| Schema evolution | free-form local migration | additive-only after production promotion (Apple, above) |
| Testing | `swift test` with in-memory containers (`WorkoutTracker/Fixtures/UITestFixture.swift`), no credentials | CloudKit paths need account-signed-in simulators/devices and CloudKit Console verification; not exercisable in `swift test` |
| Doc alignment | ADR-0001: Sheet is single source of truth; the cache is explicitly a cache | a third data holder the coach can't see, holding derived data — inside ADR-0001's letter (derived, re-creatable) but adding exactly the infrastructure class ADR-0001 rejected ("Dedicated backend … unnecessary complexity", `docs/adr/0001:10`) |

One cost asymmetry worth recording in CloudKit's favor: if a future
requirement *does* demand multi-device (e.g. iPad in the gym + phone), the
local-only extension has no path to it other than re-running the fill per
device — which, per §4, is a one-time ~29-request sweep per device, i.e. the
"missing" capability costs roughly one minute of quota per additional device.

---

## 3. Scale check

The #339 audit sizes full extracted history at ~1,000–5,000 rows of a few
short strings plus a date (~150–300 bytes each), well under 1 MB total
(audit §Option A, "Storage shape"). Facts grounding "SwiftData/SQLite handles
this trivially on-device":

- The app *already* loads the entire `LastPerformedEntry` table into memory on
  every refresh — `LastPerformedIndex.snapshot()` is an unfiltered
  `context.fetch(FetchDescriptor<LastPerformedEntry>())`
  (`WorkoutTracker/Progress/LastPerformedIndex.swift:27-30`), called from
  `LastPerformedLookupStore.refresh()` on the main actor
  (`WorkoutTracker/Stores/LastPerformedLookupStore.swift:25-27`) — and this is
  invoked once per backfilled tab (`SyncCoordinator.swift:244`) with no
  observed cost. A 5k-row table is the same order of work.
- The heaviest existing per-sync operation is already far larger than any
  history query: `replacePersistedBlock` deletes and re-inserts the entire
  `Block → Week → Session → Exercise → ExerciseSet` graph on every sync
  (`SyncCoordinator.swift:147-154`), and `localLoggedAtBySetID` walks every
  persisted set (`SyncCoordinator.swift:299-322`). History reads would be
  indexed point queries (`fullName`/`baseName` predicates, the same two-tier
  shape as `LastPerformedIndex.lookup`, `LastPerformedIndex.swift:12-25`)
  over ≤5k rows.
- There is no load for a cloud tier to relieve: CloudKit mirroring does not
  reduce on-device storage (§1.1), does not make queries faster (queries run
  against the local store), and the dataset is ~3 orders of magnitude below
  anything where device storage or SQLite query performance becomes a design
  input. No fact found in the repo or Apple's docs suggests otherwise.

---

## 4. Device-side performance of the initial ~27-tab fill (regardless of storage choice)

Whatever store the rows land in, the fill itself is: ~27 × (1 HTTPS GET +
JSON decode + grid parse + extract + ingest) on the athlete's device. CloudKit
changes none of this for the first device; it would only spare *additional*
devices the refill.

### 4.1 What the existing backfill pattern already provides (verified in code)

- **Deferred, non-blocking launch:** `sync()` finishes the current-Block work
  first, then `launchLastPerformedBackfill` spawns an unstructured `Task`
  (`SyncCoordinator.swift:197-215`). Sync triggers are: first launch with an
  empty store (`WorkoutTracker/Views/SessionView.swift:92-100`), sheet
  selection/switch (`WorkoutTracker/Stores/SettingsStore.swift:222,320`), and
  Developer Tools (`WorkoutTracker/Views/DeveloperToolsView.swift:231`).
- **Off-main-actor fetch+parse at background QoS:** each tab's network fetch,
  JSON decode, and `SheetParser().parse` run inside
  `Task.detached(priority: .background)`
  (`SyncCoordinator.swift:230-236, 256-264`) — the expensive per-tab work is
  off the main actor and system-throttled, which is also the right battery
  primitive. (Contrast: the *current* tab's parse in `sync()` runs on the
  main actor, `SyncCoordinator.swift:119`, since `SyncCoordinator` is
  `@MainActor`, line 4 — existing behavior, unaffected by history.)
- **Main-actor work per tab is small but real:** `ingest` + `context.save()`
  and a full-table snapshot rebuild happen back on the main actor per tab
  (`SyncCoordinator.swift:243-244`; the context is the container's
  `mainContext`, `WorkoutTrackerApp.swift:48`). Over 27 tabs that is 27
  save+rebuild hops — fine at ≤5k rows (§3), but the snapshot rebuild is
  O(table) per tab, a mildly quadratic pattern to be aware of if refresh
  granularity stays per-tab.
- **One tab at a time, strictly sequential** (`for tab in historicalTabs`
  with `await` per iteration, `SyncCoordinator.swift:227-253`) — no
  parallel burst.
- **Partial fill survives app kill:** each tab's records are persisted
  immediately (`ingest` ends in `try context.save()`,
  `LastPerformedIndex.swift:46`), so rows already ingested are durable. The
  backfill re-launches on every subsequent sync (`SyncCoordinator.swift:133-138`).

### 4.2 What is missing (verified absences)

- **No rate-limit handling — confirmed.** A repo-wide search for
  `429`/`backoff`/`retryAfter`/`Retry-After`/`rateLimit` in `WorkoutTracker/`
  finds nothing. The client maps every non-2xx status to
  `SheetsError.http(status)` with no inspection
  (`WorkoutTracker/Sheets/GoogleSheetsClient.swift:184-190`), and the backfill
  loop's only error handling is `catch { continue }`
  (`SyncCoordinator.swift:237-239`) — a 429 mid-sweep silently skips that tab.
  For Last Performed the coverage guard usually retries implicitly on the next
  sync; for a *full* history fill, a silently skipped tab is a permanent gap
  until an explicit re-scan policy exists.
- **Google's official quota numbers:** 300 read requests/min/project and
  **60 read requests/min/user/project** (same numbers for writes); exceeding
  them "generates a `429: Too many requests` HTTP status code response," and
  Google's documented remedy is exponential backoff
  (`min(((2^n)+random_number_milliseconds), maximum_backoff)`) —
  [Sheets API usage limits](https://developers.google.com/workspace/sheets/api/limits).
  A full fill is ~29 reads (1 `listTabTitles` + 1 current tab in `sync()`,
  `SyncCoordinator.swift:109,117`, + ~27 historical tabs) — inside one
  minute's per-user budget, but back-to-back with zero headroom: any
  concurrent read (a re-triggered sync, `flushPending`'s per-tab
  `gridSnapshot` fetches at `SyncCoordinator.swift:632`, the sheet picker's
  Drive listing) shares the same 60/min budget.
- **No throttling:** there is no delay between tab fetches; the sequential
  loop is the only pacing.
- **No resumability cursor:** nothing records which tabs have been processed.
  Today that is fine — the coverage guards (`SyncCoordinator.swift:224,
  250-252`) stop after 1–2 tabs and make re-launched backfills near-free. A
  full-history fill removes those guards (audit §Option A), so an app kill at
  tab 20 means the next launch re-fetches tabs 1–19 unless per-tab completion
  (e.g. an ingested-tab marker keyed on `source` tab name) is added.
  Idempotency is not the problem — re-ingest keyed on (`fullName`, `source`)
  is a no-op — the ~19 wasted quota reads are.
- **No error propagation:** the backfill's ingest failure sets
  `state = .conflict` and aborts (`SyncCoordinator.swift:245-248`), but
  fetch/parse failures are invisible to the athlete and to any telemetry;
  `LastPerformedBackfillObserving` fires only on completion
  (`SyncCoordinator.swift:213`), with no per-tab progress signal a history
  UI could show.

### 4.3 Parse cost and battery envelope

Per-tab payload is capped by the fields mask to `formattedValue` + row
visibility (`GoogleSheetsClient.swift:138-141`) — tens of KB per tab (#339
audit §Option C). Parsing is single-pass string scanning over a grid of a few
hundred rows per tab; 27 tabs of that at `.background` QoS is seconds of
throttled CPU, not a battery event. The dominant cost is the ~27 sequential
network round-trips, which the OS radio already amortizes since they are
back-to-back. No fact found suggests the fill needs more than the missing
items in §4.2 (backoff on 429, optional inter-tab pacing, a per-tab
completion marker) to be robust.

---

## What the facts constrain (not a decision)

1. Any CloudKit design must first do the same schema work the local extension
   needs (drop `@Attribute(.unique)` on the history model, app-level dedupe on
   (`fullName`, `source`)) — CloudKit adds requirements on top of, never
   instead of, the local path.
2. Nothing CloudKit stores here would be a source of truth: ADR-0001 pins that
   to the Sheet, and every history row is re-derivable from it. Whatever is
   decided, the CloudKit copy could only ever be a replicated cache of a cache.
3. The 27-tab fill's robustness gaps (429 backoff, resumability marker, silent
   tab-skip) exist in the Sheets client and backfill loop, and must be fixed
   there regardless of the storage decision.
4. At ≤5 k rows / ≤1 MB there is no performance or capacity fact that forces —
   or even nudges toward — a second storage tier; the only fact that could is
   a multi-device product requirement, which no current product doc states.
