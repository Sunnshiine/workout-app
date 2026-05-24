# High-Level App Design — iOS Workout Tracker

**Date:** 2026-05-24
**Status:** Approved (design session)
**Builds on:** PRD ([issue #1](https://github.com/Sunnshiine/workout-app/issues/1)), `CONTEXT.md` (domain glossary), and ADRs 0001–0003.

This document translates the PRD's *what* (modules, responsibilities, data model, test plan) into the *how*: the concrete SwiftUI architecture — navigation, module composition, persistence schema, data flow, and the sync state machine. Domain terms (Block, Session, Set Log, Open Exercise, Last Performed, etc.) are used per `CONTEXT.md`.

---

## Baseline decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | **iOS 26** deployment target | Single-athlete app on a modern device; unlocks SwiftData, `@Observable`, NavigationStack, Liquid Glass with no back-compat burden. |
| 2 | **`@Observable` stores in the environment** (not MVVM-per-screen, not Redux) | Only 3 screens; the PRD's logic already lives in pure engines. A thin observable layer is the least machinery that does the job. |
| 3 | **GoogleSignIn SDK + thin URLSession REST client** | GoogleSignIn owns the fiddly OAuth refresh + Keychain; a thin client keeps the two Sheets endpoints transparent for the safety-critical write path. Sits at the intersection of robust auth and write-path control. |
| 4 | **SwiftData persists the full current Block + Last Performed index + pending write queue** | True local-first (ADR 0001): a no-signal cold launch at the gym still shows today's Session. |
| 5 | **Coordination layer = three focused `@Observable` stores** (`WorkoutStore`, `SyncCoordinator`, `SettingsStore`) | Clear single-responsibility boundaries, each independently testable, no god-object, no extra repository layer. |

---

## 1. Navigation & view hierarchy

A single `NavigationStack`, never more than one Session deep. A first-run gate handles sign-in before the main app appears.

### App entry & onboarding gate

```
WorkoutApp (@main)
  └── RootView — switches on SettingsStore.isConfigured
        ├── [not configured] → OnboardingView
        │        • Sign in with Google (GoogleSignIn)
        │        • Paste training Sheet URL
        └── [configured]     → NavigationStack(path)   // path is empty or just [.blockOverview]
```

### Main navigation (when configured)

- **`SessionView`** — root. Renders `displayedSession` (defaults to the current Session). Contains:
  - breadcrumb *"Block N · Week N"* → pushes Block Overview
  - toolbar gear → presents Settings (modal sheet)
  - exercise list: prescribed Sets · Coach Note · per-set input · Last Performed · Load Suggestions
  - inline **Open Exercises** (makeup queue, scoped to the Current Week)
  - **"Move On"** → advances the current Session (shown only when viewing the live edge)
- **`BlockOverviewView`** — pushed via the breadcrumb (one level). 4×4 grid of 16 Sessions, tiles colour-coded by state. **Tapping a tile sets `displayedSession` and pops back to root** — the grid is a *switcher*, not a drill-in. The stack is never deeper than Session → Overview.
- **`SettingsView`** — modal sheet. Sheet URL · Google account · manual re-sync · sign out.

### Key navigation decisions

- **One `SessionView` type** serves both the live current Session (root) and any Session tapped from the grid — it just renders whichever Session it's handed.
- **`displayedSession` vs `currentSession`** — the root shows `displayedSession` (what you're looking at); `currentSession` is the live edge (where "Move On" lands and what launch shows). Both live on `WorkoutStore`. "Move On" advances `currentSession` and resets `displayedSession` to it.
- Settings is a **modal sheet** (iOS convention); Block Overview is **pushed** (natural drill-down).

---

## 2. Module dependency graph

Layered; every dependency points downward ("uses"). Most engines are pure (no downward dependency); the Sheet Writer and API Client isolate all network I/O, and the Last Performed Index works over the store — so each unit tests against fixtures or a single stubbed boundary, matching the PRD test plan.

```
SwiftUI views        RootView · OnboardingView · SessionView · BlockOverviewView · SettingsView
                                   │  read via .environment()
                                   ▼
@Observable stores   WorkoutStore        SyncCoordinator        SettingsStore
                                   │  use
                                   ▼
Pure engines &       Sheet Parser · Sheet Writer · Session Progress Tracker ·
clients              Load Suggestion Engine · Last Performed Index · Sheets API Client
                                   │
                                   ▼
Infra / external     SwiftData (Block · index · queue) · GoogleSignIn SDK · Google Sheets REST API
```

### The three stores

- **`WorkoutStore`** — holds the Block, `currentSession` / `displayedSession`, and derived progress; performs **optimistic** local logging. Reads the Block from SwiftData; uses Session Progress Tracker, Load Suggestion Engine, and Last Performed Index to feed the views. On a log: writes the SetLog locally + enqueues, then calls `SyncCoordinator.flushPending()`.
- **`SyncCoordinator`** — the sync state machine; **owns all network**. Read path (API Client + Parser), write path (Sheet Writer), clears the queue in SwiftData, and drives Last Performed backfill (fetch prior tabs → parse → `index.ingest()`).
- **`SettingsStore`** — Sheet URL, auth state, `isConfigured`. Talks to GoogleSignIn and AppStorage; not SwiftData.

### Key edges (the non-obvious ones)

- **`Sheet Writer` → `Sheets API Client`** for its read-before-write + write. The **API Client is the only thing that touches GoogleSignIn + the REST API** — one network choke point.
- **Last Performed Index is network-free**: it does lookups and `ingest()`s parsed results, but the *fetching* of historical tabs is orchestrated by `SyncCoordinator`. This keeps the Index unit-testable against a fixture store (per the PRD).
- **No store-to-store cycles.** The only inter-store call is `WorkoutStore → SyncCoordinator.flushPending()`. Results flow *back* through SwiftData, which both stores observe — so a finished sync re-renders views with no callback.

---

## 3. SwiftData schema

Three persisted concerns: the one current Block (full hierarchy), the flattened Last Performed index, and the pending write queue. Settings live outside SwiftData.

### Block hierarchy — `@Model` classes (cascade delete from Block)

```
Block      tabName (id) · trainingMaxes { squat · bench · deadlift }
  └ Week        number 1–4                                            ×4
     └ Session     dayNumber 1–4 · date                               ×4 (Day 1–4)
        └ Exercise    name (with cadence) · baseName (cadence stripped) · coachNote
           └ Set         index · prescribedReps · prescribedLoad · percentOneRM · state · setLog?
                └ SetLog (embedded Codable value)   weight (lbs | "BW") · reps (Int) · rpe (Double, 0.5 steps)
```

`state` is the Set State enum: `pending` / `logged` / `skipped` (per `CONTEXT.md`).

### `LastPerformedEntry` — `@Model`

- `@Attribute(.unique) fullName` — exact name including cadence (tier-1 lookup key)
- `baseName` — cadence-stripped fallback key (tier-2 lookup)
- `result: SetLog` · `performedOn: Date`
- `source` — e.g. "Block 26 · W3 D1" (display label)

**Only Logged results are ever stored.** Skipped occurrences are never written as entries, so the "skip over Skipped, continue backwards" rule (ADR 0002) is satisfied for free at lookup time.

### `PendingWrite` — `@Model`, FIFO queue

- `id` · `createdAt` (FIFO ordering)
- **semantic target**: `blockTab` · `week` · `day` · `exerciseName` · `setIndex` · `column { .notes | .lastSetRPE }`
- `operation { .upsert | .delete }` · `valueToWrite: String?` — e.g. "185x7@6", "8", "skip"
- **`expectedCurrentValue: String`** — the optimistic lock (empty for a new log; the prior value for edit/delete)
- `status { .pending | .conflict }` · `retryCount` · `lastError: String?`

**Targets the cell semantically — never by coordinates (ADR 0003)** — and stores plain value-type identity (no relationship to a `Set` object), so the queue **survives a Block refresh**.

### Behaviour

- **One Block at a time.** Sync refreshes the current Block in place; history exists only as flattened `LastPerformedEntry` rows — old Block hierarchies are never retained (ADR 0002).
- **Optimistic logs stay visible.** The SetLog on `Set` is the local truth; on each refresh, still-pending writes are re-overlaid so un-synced logs don't vanish (see §4, R5). Even a `.conflict` write stays overlaid — it's the athlete's truth locally; we just keep warning that the sheet write didn't land.
- **Settings aren't in SwiftData.** Sheet URL + spreadsheet ID → AppStorage; Google tokens → GoogleSignIn's Keychain.

---

## 4. Data flow

Views never touch the network — they observe SwiftData + the `SyncCoordinator`'s published state. The two paths converge on SwiftData.

### Read path — sync / launch / pull-to-refresh / reconnect

1. Trigger: launch · pull-to-refresh · reconnect.
2. **Flush the queue first** (write path) so the sheet is current before we read back.
3. API Client → `batchGet`(current tab). *[network]*
4. Sheet Parser → Block model (+ parse warnings).
5. **★ Overlay still-pending writes** onto the fresh Block, so un-synced logs don't vanish.
6. Persist Block in SwiftData (refresh in place) · detect a newer tab → it becomes current (PRD user story 32).
7. `WorkoutStore` observes → Session Progress Tracker derives session/week/open/tiles → views re-render.
8. *Background:* Last Performed backfill if the index doesn't cover every current Exercise (fetch prior tabs → parse → `ingest`).

### Write path — logging a Set

1. `SessionView`: enter `{weight}x{reps}@{rpe}` or tap Skip → `WorkoutStore.log()`.
2. **★ Optimistic local write**: SetLog onto the Set, `state = logged` → UI updates instantly.
3. Update Last Performed Index · enqueue PendingWrite(s) — including a Last-Set-RPE write on the final Set.
4. Call `SyncCoordinator.flushPending()`.
5. *[online]* Sheet Writer, per entry: **★ `batchGet` to resolve column (header scan) + row (exercise-anchor scan)** — dynamic, never coordinates.
6. **★ Read the cell → compare to `expectedCurrentValue`.**
7. **match** → `batchUpdate` → dequeue. **mismatch** → `status = .conflict`, warn, no write.
8. network error → retain in queue, retry with exponential backoff.

**Convergence:** A log feels instant (W2) while the sheet write happens behind it (W5–7), and a refresh never loses an un-synced log (R5). Every write is dynamically targeted and verified end-to-end (W5–6) per ADR 0003.

---

## 5. Sync state machine

A single `state` published by `SyncCoordinator`, surfaced in `SessionView` as a small status by the breadcrumb (and a banner for conflict). Core loop: **`idle ⇄ syncing`**; three outcome states each return to `syncing`.

| State | Enters when | Athlete sees | Leaves → |
|---|---|---|---|
| **idle** | sync done, queue empty, online | subtle "Synced · {time}" | syncing — on launch · pull-to-refresh · a new log · reconnect |
| **syncing** | any trigger | spinner / "Syncing…" | idle (clean) · or one of the three below |
| **pendingWrites** | online, queue still non-empty after a flush (network error → backoff) | "{N} unsynced" · tap to retry | syncing — on retry timer / next trigger |
| **offline** | network path is down | "Offline — {N} saved locally, will sync when you're back" | syncing — on reconnect (path monitor) |
| **conflict** | a write failed verify (cell mismatch) or a parse/targeting warning | banner: "Couldn't write to your sheet — check {exercise}" · per-item retry/discard | syncing — on next sync / retry; clears once the mismatch resolves |

**Local logging never blocks on any of this** — the SetLog is already saved (W2). These states describe only the *sheet* relationship, so the gym experience stays smooth offline or mid-conflict.

---

## Module inventory (PRD → this design)

| PRD module | This design | Kind |
|---|---|---|
| Sheet Parser | `SheetParser` | pure type |
| Sheet Writer | `SheetWriter` (uses API Client) | pure-ish (I/O via client) |
| Sheets API Client | `SheetsAPIClient` (GoogleSignIn token + URLSession) | client |
| Sync Engine | `SyncCoordinator` | `@Observable` store |
| Local Store (SwiftData) | SwiftData models + `ModelContext` | infra |
| Last Performed Index | `LastPerformedIndex` (+ `LastPerformedEntry` model) | pure logic over store |
| Load Suggestion Engine | `LoadSuggestionEngine` | pure type |
| Session Progress Tracker | `SessionProgressTracker` | pure type |
| — (UI state for workout) | `WorkoutStore` | `@Observable` store |
| — (settings/auth) | `SettingsStore` | `@Observable` store |

---

## Testing posture

Per the PRD: a good test exercises a module's public interface with realistic inputs and asserts on observable outputs — no mocking of internal collaborators; only stub the I/O boundaries (Sheets API, local store). Sheet Parser, Session Progress Tracker, and Load Suggestion Engine are pure (input → output), tested directly against fixtures. Last Performed Index is pure logic over an in-memory store. Sheet Writer and the API Client concentrate all network I/O, tested against a stubbed Sheets API returning preconfigured cell values. The stores are thin enough to test by driving their public methods against an in-memory `ModelContext` + a stubbed `SheetsAPIClient`.

---

## Out of scope

Unchanged from the PRD's Out of Scope section (multi-athlete, push notifications, historical block browsing, charts/analytics, body weight/nutrition, custom exercise library, non-Block sheet tabs, optional Off Days column, Watch/widgets, Android).
