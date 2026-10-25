# workout

<!-- doc-symbols: not-in-tree manifest.json workbook.json labels.json -->

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

The home also holds `settings.json`: the selected spreadsheet, the appearance, and each Block
tab's Current Session Pin, rewritten after every change. `init` resets it with the rest of the
home, and deleting or moving the home takes it along. A home made before settings moved into it is refused
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
| `init [--scenario <name>]` (`init --help` lists every `WorkbookScenario`) | wipes the home, seeds the workbook, `selectSpreadsheet` (the onboarding path, which syncs) | home, scenario, spreadsheet, Block summary, Current Session |
| `status` | `snapshot()` | sync outcome, pending write count, Current Session and why, Session index |
| `session [w1d1]` | `session(_:)` | one Session; every Exercise and Set carries its address. No address means the Current Session |
| `log w1d1.e0.s0 185x5@8` | `WorkoutStore.log(_:as:)` | the Set, the pending write count, whether the Exercise is complete. No auto-flush |
| `skip w1d1.e0.s0` | `WorkoutStore.skip(_:)` | the same report `log` prints. No auto-flush |
| `delete-log w1d1.e0.s0` | `WorkoutStore.deleteLog(for:)`, the card's Clear; a Pending Set writes nothing | the same report `log` prints. No auto-flush |
| `move-on` | `requestMoveOnCelebration()`, the Move On button, then `dismissMoveOnCelebration()`, the tap that ends the celebration, in one process | `returnedToBlockGrid`, true when no Available Session remained ahead, and the snapshot `status` prints |
| `make-current w2d1` | `view(_:)`, then `makeCurrent()`, the Make current control's `WorkoutStore.makeViewedSessionCurrent()`, in one process; an Unavailable Session is refused | the snapshot `status` prints |
| `say w1d1.e0.s0 "185 for 5 at 8"` | `SpokenSet.parse`, then `WorkoutStore.log(_:as:)` or `WorkoutStore.skip(_:)` | what it heard, its outcome, and the same report `log` prints. No auto-flush |
| `hear w1d1.e0.s0 set.aiff` | `SpeechListening.transcripts(of:installing:)`, the mic's speech model, then `dictate(_:at:)` | the transcripts it heard as `candidates`, plus what `say` prints for the most likely. No auto-flush |
| `flush` | `SyncCoordinator.flushPending` | attempted, written, conflicted writes, remaining, sync outcome |
| `sheet [--tab T] [--cell K15]` | `SheetsClient.fetchTabSnapshot` | every non-empty cell, or one cell's value |
| `sync [--viewing w2d3]` | `view(_:)` when `--viewing` is given, then `SheetConnection.syncNow()`, the Sync now button's call, which syncs and then reloads | sync outcome, Block summary, Current Session, Viewed Session, pending write count, conflicted writes |
| `dictations summary records.jsonl [--labels labels.json]` | `WorkoutApplication.dictationSummary(reading:labels:)`, over a journal file or a `Dictation Records` directory copied off a phone; it opens no home | presses by surface and end, outcomes under the shipped rule and under each `MergeRule`, engine agreement, Recording Transcripts read and missed by reason, release-to-outcome wait against the 500 ms target with the cause of each miss, `implausible` rejections by engine and field, `promptEcho`, stall and footprint percentiles, unreadable lines, and the caveats. With labels, `scored` counts the outcome that decided each press as CORRECT, WRONG, or NOWRITE |
| `dictations replay records.jsonl [--labels labels.json]` | `WorkoutApplication.dictationReplay(reading:labels:)`, over the same files; it opens no home | per Speech Model version, the rule that decided each press, and for each `MergeRule` its outcomes and how many presses it decides differently. With labels, each rule's `scored` |

`init`, `sync`, and `flush` converge: running them twice gives the same state. `log` twice
enqueues twice, because that is what the store does; the report shows it. `delete-log` on a
Pending Set enqueues nothing, so a stale local view cannot queue a conflicted write that no
command can discard yet.

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

## Spoken Sets and recordings

`say` and `hear` read a Spoken Set from a transcript or a recording.
[SPOKEN_SETS.md](SPOKEN_SETS.md) covers both.

## Dictation Records

Settings > Speech > Export shares one archive, `Dictation Records.zip`, through
the share sheet. It holds the phone's journal as `records-YYYY-MM.jsonl` files, a `labels.json`,
and, once iOS has delivered any, a `MetricKit` folder of its hang and memory payloads. The export labels each
record whose outcome wrote a Set with what that Set holds now, read from the cached Block. The
same Set Log means the write stood, another means the athlete corrected it, and Pending means they
cleared it. A record whose Set is gone, because the Block moved on or the Exercise changed, has no
label.

`replay` scores those presses under every `MergeRule` from the outcomes each record kept in
`byRule`, so `lead`, which ships, can be weighed against `gate` on real presses. It groups them by
the Speech Model version that read their recordings, so a model or prompt change never blurs into
one count. `differsFromDecided` counts the presses a rule decides differently from the rule that
decided them, by what each does to the Set and the card. Without `--labels` it reports only that,
and says so. With them, each rule scores the labelled presses in the classes
`scripts/measure-dictation.sh` uses, through the one `DictationScoring.classify` that `summary`
scores with.

```console
$ ditto -x -k ~/Downloads/"Dictation Records.zip" ~/Downloads && cd ~/Downloads/"Dictation Records"
$ workout dictations replay . --labels labels.json \
    | jq -c '.versions[0].rules | map_values(.scored)'
{"gate":{"CORRECT":1,"NOWRITE":1,"WRONG":0,"unscored":2},"lead":{"CORRECT":1,"NOWRITE":0,"WRONG":1,"unscored":2},...}
```

Labels exist only where the deciding rule wrote, so that rule never scores NOWRITE, and a write
another rule would make on a press nothing wrote goes unscored. A correction is a lower bound on
wrong writes, since an athlete who never notices a wrong write never corrects it. Both caveats
print with the scores.

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
| 69 | unavailable (`hear` on a Mac with no on-device speech-to-text) |
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

A new capability is a facade method on `WorkoutApplication` that calls the store method the
UI calls, plus one file in `Commands/`. A command is one gesture, and a gesture whose state lives
in memory makes all its facade calls in one process (`move-on`, `make-current`). The CLI imports
`WorkoutTracker` without `@testable`, so it cannot reach a store directly. `init` is the one
deliberate exception: it seeds the workbook file and the manifest before an application exists,
and it is the only command that does. Next in line: `pending-writes`
(`SyncCoordinator.pendingWriteDiagnostics`) and `discard-writes`
(`SyncCoordinator.discardPendingWrites`). Add a scenario by adding a case to
`WorkbookScenario`; the scenario test requires it to parse with no warnings. Every UI launch
Scenario flag is its workbook's name in upper snake case (`-UITEST_FULL_BLOCK` boots `full-block`),
and a launch that names none boots `partial-upload`, so the CLI and the UI suites read the same
cells under the same names. A misspelt flag stops the UI boot.

The Exercise History fill runs as a fire-and-forget task after a multi-tab sync; a CLI process
exits before it runs, so scenarios in this slice have one tab. See ADR-0015.
