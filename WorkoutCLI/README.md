# workout

A headless client for the WorkoutTracker application. It runs the same stores the iOS app
runs, against a local workbook file instead of Google Sheets, and prints JSON. It exists so a
coding agent can inspect and change application state on the desktop in milliseconds.

## Build

```console
$ swift build --product workout        # .build/debug/workout
$ swift test                           # includes the binary test in Tests/Component/WorkoutCLIBinaryTests.swift
```

## Home

Every command works on a home directory: `--home <dir>`, else `$WORKOUT_HOME`, else `./.workout-cli`.
It holds `manifest.json` (the ownership marker: scenario, spreadsheet id, version), `store.sqlite`
(the SwiftData cache), and `workbook.json` (the Sheet). `init` only wipes a path that does not
exist, an empty directory, or a directory carrying this tool's manifest; a file or a foreign
directory is refused with exit 3.

UserDefaults (the selected spreadsheet, the Current Session override) live in a suite named
`WorkoutTracker.cli.<first 16 hex of sha256(home path)>`, so two homes never share a key. The
suite is a plist under `~/Library/Preferences`, not a file in the home: `init` wipes it, deleting
the home directory does not. A key-value seam that keeps it inside the home is the next step
(ADR-0015).

`workbook.json` is a sparse A1 map you can edit by hand:

```json
{ "spreadsheetId": "FIXTURE", "title": "Fixture Training Log",
  "tabs": { "Block 27": { "rows": 60, "cols": 60,
    "cells": { "C12": "Day 1", "C15": "Back Squat", "K15": "185x5@8" },
    "hiddenRows": { "20": { "hiddenByUser": true, "hiddenByFilter": false } } } } }
```

## Commands

| Command | Calls | Prints |
|---|---|---|
| `init [--scenario fresh-block]` | wipes the home, seeds the workbook, `selectSpreadsheet` (the onboarding path, which syncs) | home, scenario, spreadsheet, Block summary, Current Session |
| `status` | `snapshot()` | sync state, pending write count, Current Session and why, Session index |
| `session [w1d1]` | `session(_:)` | one Session; every Exercise and Set carries its address. No address means the Current Session |
| `log w1d1.e0.s0 185x5@8` | `WorkoutStore.log(_:as:)` | the Set, the pending write count, whether the Exercise is complete. No auto-flush |
| `skip w1d1.e0.s0` | `WorkoutStore.skip(_:)` | the same report `log` prints. No auto-flush |
| `flush` | `SyncCoordinator.flushPending` | attempted, written, conflicted writes, remaining, sync state |
| `sheet [--tab T] [--cell K15]` | `SheetsClient.fetchTabSnapshot` | every non-empty cell, or one cell's value |
| `sync [--viewing w2d3]` | `view(_:)` when `--viewing` is given, then `SyncCoordinator.sync` and `reload` | sync state, Block summary, Current Session, Viewed Session, pending write count, conflicted writes |

`init`, `sync`, and `flush` converge: running them twice gives the same state. `log` twice
enqueues twice, because that is what the store does; the report shows it.

The Viewed Session is transient view state that dies with the process, so `sync --viewing w2d3`
is the only way to watch what a reload does to it: it opens that Session the way the Block grid
does, syncs, and reports where the athlete ended up. At the live edge `viewedSession` follows
`currentSession`; browsed away it stays put (`.claude/work/viewed-session-across-sync.sh`).

A write the Sheet rejects (its cell no longer holds the expected value) is marked `conflict` and
never retried, exactly as in the app. `flush` and `sync` print the report to stdout, list it under
`conflictedWrites` on every later run, and exit 4 until it is discarded, so a retry cannot read
"nothing left to attempt" as "everything landed". Discarding is the next verb (`discard-writes`).

## Addresses

Domain numbers verbatim. `w<week>d<day>` is 1-based (Week number, Day number).
`.e<order>` is `Exercise.order`, 0-based. `.s<index>` is `ExerciseSet.index`, 0-based.
Parsing is strict (`w1d1.e0.s2`, never `W1D1`). Copy ids from `session` output.

## Output and exit codes

Results are pretty JSON on stdout (sorted keys, ISO-8601 dates). Errors are one JSON line on
stderr; stdout is empty unless the command produced a report before failing (a `flush` that left
conflicts behind prints the report, then the error):

```console
$ workout log w1d1.e0.s9 185x5@8; echo $?
{"error":{"candidates":["w1d1.e0.s0","w1d1.e0.s1","w1d1.e0.s2"],"code":"unknown_set","message":"w1d1.e0 has 3 Sets; no Set at w1d1.e0.s9."}}
1
```

| Exit | Meaning |
|---|---|
| 0 | ok |
| 1 | domain error (an address or state error; `code` names it) |
| 3 | environment error (no home, unreadable workbook, sheet offline) |
| 4 | conflict (a queued write the Sheet rejected, or `sync` ended in conflict) |
| 64 | usage (ArgumentParser) |
| 70 | internal (an error the CLI did not classify; the message is the raw description) |

`WORKOUT_NOW=2026-05-28T20:26:40Z` freezes the clock for reproducible `loggedAt` values. A
value that is not ISO-8601 is an environment error, not a silent fallback.

## The arc

```console
$ export WORKOUT_HOME=$(mktemp -d)
$ workout init --scenario fresh-block
$ workout session | jq '.exercises[0].sets[0].id'    # "w1d1.e0.s0"
$ workout log w1d1.e0.s0 185x5@8
$ workout flush
$ workout sheet --cell K15                            # "185x5@8"
$ workout sync
$ workout session w1d1 | jq '.exercises[0].sets[0].state'   # "logged", parsed from the Sheet
```

## How it grows

A new capability is one facade method on `WorkoutApplication` that calls the store method the
UI calls, plus one file in `Commands/`. The CLI imports `WorkoutTracker` without `@testable`, so
it cannot reach a store directly. `init` is the one deliberate exception: it seeds the workbook
file and the manifest before an application exists, and it is the only command that does. Next in
line: `delete-log` (`WorkoutStore.deleteLog(for:)`), `move-on` (`WorkoutStore.moveOn`),
`pending-writes` (`SyncCoordinator.pendingWriteDiagnostics`), and `discard-writes`
(`SyncCoordinator.discardPendingWrites`). Add a scenario by adding a case to
`WorkbookScenario`; the scenario test requires it to parse with no warnings.

The Exercise History fill runs as a fire-and-forget task after a multi-tab sync; a CLI process
exits before it runs, so scenarios in this slice have one tab. See ADR-0015.
