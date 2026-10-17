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

The home also holds `settings.json`: the selected spreadsheet, the appearance, and the Current
Session override, rewritten after every change. `init` resets it with the rest of the home, and
deleting or moving the home takes it along. A home made before settings moved into it is refused
with exit 3; run `init` again.

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
| `status` | `snapshot()` | sync outcome, pending write count, Current Session and why, Session index |
| `session [w1d1]` | `session(_:)` | one Session; every Exercise and Set carries its address. No address means the Current Session |
| `log w1d1.e0.s0 185x5@8` | `WorkoutStore.log(_:as:)` | the Set, the pending write count, whether the Exercise is complete. No auto-flush |
| `skip w1d1.e0.s0` | `WorkoutStore.skip(_:)` | the same report `log` prints. No auto-flush |
| `say w1d1.e0.s0 "185 for 5 at 8"` | `SpokenSet.parse`, then `WorkoutStore.log(_:as:)` or `WorkoutStore.skip(_:)` | what it heard, its outcome, and the same report `log` prints. No auto-flush |
| `flush` | `SyncCoordinator.flushPending` | attempted, written, conflicted writes, remaining, sync outcome |
| `sheet [--tab T] [--cell K15]` | `SheetsClient.fetchTabSnapshot` | every non-empty cell, or one cell's value |
| `sync [--viewing w2d3]` | `view(_:)` when `--viewing` is given, then `SheetConnection.syncNow()`, the Sync now button's call, which syncs and then reloads | sync outcome, Block summary, Current Session, Viewed Session, pending write count, conflicted writes |

`init`, `sync`, and `flush` converge: running them twice gives the same state. `log` twice
enqueues twice, because that is what the store does; the report shows it.

The Viewed Session is transient view state that dies with the process, so `sync --viewing w2d3`
is the only way to watch what a reload does to it: it opens that Session the way the Block grid
does, syncs, and reports where the athlete ended up. At the live edge `viewedSession` follows
`currentSession`; browsed away it stays put (`scripts/viewed-session-across-sync.sh`).

A write the Sheet rejects (its cell no longer holds the expected value) is marked `conflict` and
never retried, exactly as in the app. `flush` and `sync` print the report to stdout, list it under
`conflictedWrites` on every later run, and exit 4 until it is discarded, so a retry cannot read
"nothing left to attempt" as "everything landed". Discarding is the next verb (`discard-writes`).

Every Set that `session`, `log`, and `skip` print carries `loadSuggestion`, the weight the Set card
pre-fills. Its `kind` is `weight` (a Drop or a %1RM), `bodyweight`, `estimate` (read through the
RPE Table from a Set Log), or `none`, which is also every Set that holds a Set Log. An `estimate`
names its Load Basis: `origin` `today` with the `set` it was logged on, or `history` with the
entry's `session`, plus the `setLog` and the `text` the card shows.

```console
$ workout log w1d1.e0.s0 315x5@7 > /dev/null
$ workout session w2d1 | jq -c '.exercises[0].sets[0].loadSuggestion'
{"basis":{"origin":"history","session":"Block 27 · W1 D1","setLog":"315x5@7","text":"from 315x5@7 · W1 D1"},"kind":"estimate","weight":315}
```

## Spoken Sets

`say` reads a transcript as a Spoken Set and does what the Set card would do with it. Each value
said replaces the one the card pre-fills (the Set's own Set Log, else `loadSuggestion` and the
prescribed reps and RPE), and the rest keep the pre-fill. A weight or reps the athlete did not say
and the card does not hold is never guessed.

| `outcome` | Means | Carries | Exit |
|---|---|---|---|
| `logged` | weight, reps, and RPE are all present, logged through `WorkoutStore.log` | `setLog` | 0 |
| `skipped` | "skip", "skip it", "skip set", or "skip this set", through `WorkoutStore.skip` | | 0 |
| `missingValues` | a value is still missing, so nothing is queued and the Set stays Pending | `missing`: `weight`, `reps`, `rpe` | 0 |
| `rejected` | the transcript is not a Set, so nothing is queued | `rejection`: `reason`, and `field` or `value` | 1 |

`rejection.reason` is `nothingHeard`, `unrecognized`, `kilograms`, `fusedNumber` (numbers the
recognizer ran together), `ambiguous` (a transcript that reads as two Sets), `conflicting` (two
numbers for one `field`), `outOfRange` (reps outside 1 to 100, or a weight outside 0 to 2000 pounds),
`offLadderRPE` (the `value` heard is not an RPE), or `nothingToRepeat` ("same again" with no
earlier Set Log of the Exercise in the Session). A rejected `say` prints its report, then a
`spoken_set_rejected` error.

The grammar, as the tests in `Tests/Unit/SpokenSetTests.swift` pin it:

- "for", "x", "by", and "times" put the weight before them and the reps after them. Between a
  value and a number, "four", "per", and "or" are "for" too ("225 or 3 at 8.5").
- "pounds", "lbs", and "lb" label the number before them as the weight, as "£" does the number after
  it, and "reps" labels the reps.
- "RPE", "rp", "r p e", "RTE", "RTD", "RTV", and "@" label the number after them as the RPE. So does
  "at", up to 10; past 10 it is the weight ("8 reps at 135"). Before the last number, "and", "of",
  and "add" are "at" ("185 for 5 and 8").
- Numbers no word labels fill what is left, in weight, reps, RPE order ("185, 5, 8").
- Number words read as athletes say them: "one thirty five", "four oh five", "eight and a half",
  "8 1/2", "one eighty seven point five", and a clock-style "1:35" for 135. "ate" is 8, and "to" or
  "too" is 2 only where a number is asked for.
- A whole number of four or more digits is `fusedNumber`, never a weight: the recognizer wrote
  "40542" for "four oh five for two".
- A two-digit rep count said last after "for", with no RPE, whose second digit is an RPE point is
  `ambiguous`: "135 for 49" may be "135 for 4 at 9". "135 for 49 reps" logs 49 reps, and "45 for 10"
  logs, because 0 is not an RPE point.
- "bodyweight", "body weight", and "BW" are the BW weight.
- "same again", "same", "same as last", "repeat", and "again" log the Exercise's nearest earlier Set
  Log in the Session. A command with numbers in it is `unrecognized`.
- Any other word rejects the transcript rather than being skipped.

```console
$ workout say w1d1.e0.s0 "RPE 9" | jq -c '{outcome, missing}'
{"outcome":"missingValues","missing":["weight"]}
$ workout say w1d1.e0.s0 "185 for 5 at 8" | jq -c '{outcome, setLog}'
{"outcome":"logged","setLog":"185x5@8"}
$ workout say w1d1.e0.s1 "at 9" | jq -c '{outcome, setLog}'     # the card's estimate, at the RPE said
{"outcome":"logged","setLog":"180x5@9"}
```

## Sync outcome

`status`, `flush`, and `sync` print `syncOutcome`, which carries one `status` per outcome, so a
failed local write and a parser footnote never read alike. `messages` is always present and holds
the strings the step produced, verbatim. `count` appears only under `writesQueued`.

| `status` | Means | Carries |
|---|---|---|
| `clear` | nothing outstanding | |
| `localWriteFailed` | the Set Log did not reach the local store, and it is gone | `messages` |
| `sheetUnreachable` | the Sheet could not be read | |
| `writesQueued` | writes are still queued; the next flush attempts them again | `count` |
| `writesRefused` | the cell no longer held what the app expected, so the write was refused rather than overwrite the coach (ADR-0003); nothing retries it | `messages` |
| `noBlockTab` | the spreadsheet has no Block tab | |
| `parseWarnings` | the sync succeeded and the Block is cached; the parser has notes | `messages` |
| `historyFillFailed` | the sync succeeded and the Session is usable; the Exercise History fill did not | `messages` |

`sync` exits 4 on the five that want the athlete and 3 on `sheetUnreachable`. `flush` exits 3 on
`writesQueued` and `sheetUnreachable`, because writes are still queued.

## Addresses

Domain numbers verbatim. `w<week>d<day>` is 1-based (Week number, Day number).
`.e<order>` is `Exercise.order`, 0-based. `.s<index>` is `ExerciseSet.index`, 0-based.
Parsing is strict (`w1d1.e0.s2`, never `W1D1`). Copy ids from `session` output.

## Output and exit codes

Results are pretty JSON on stdout (sorted keys, ISO-8601 dates). Errors are one JSON line on
stderr; stdout is empty unless the command produced a report before failing (a `flush` that left
conflicts behind, or a rejected `say`, prints the report, then the error):

```console
$ workout log w1d1.e0.s9 185x5@8; echo $?
{"error":{"candidates":["w1d1.e0.s0","w1d1.e0.s1","w1d1.e0.s2"],"code":"unknown_set","message":"w1d1.e0 has 3 Sets; no Set at w1d1.e0.s9."}}
1
```

| Exit | Meaning |
|---|---|
| 0 | ok |
| 1 | domain error (an address or state error, or a rejected Spoken Set; `code` names it) |
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
