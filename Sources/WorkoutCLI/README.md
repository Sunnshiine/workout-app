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
| `hear w1d1.e0.s0 set.aiff` | `SpeechListening.transcripts(of:installing:)`, the mic's speech model, then `dictate(_:at:)` | the transcripts it heard as `candidates`, plus what `say` prints for the most likely. No auto-flush |
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

On the facade, `say` is `dictate(_ candidates: [String], at:)` with one transcript. `dictate` takes
a recognizer's transcripts, most likely first, under the Dictation write policy: only the most
likely transcript writes. A Set only the less likely ones read, and agree on, is `rejected` as
`ambiguous` with nothing written. The headless Dictation the Action button and Control Center run
on a locked phone writes through the same call.

| `outcome` | Means | Carries | Exit |
|---|---|---|---|
| `logged` | weight, reps, and RPE are all present, logged through `WorkoutStore.log` | `setLog` | 0 |
| `skipped` | "skip", "skip it", "skip set", "skip this set", or "skipped", through `WorkoutStore.skip` | | 0 |
| `missingValues` | a value is still missing, so nothing is queued and the Set stays Pending | `missing`: `weight`, `reps`, `rpe` | 0 |
| `rejected` | the transcript is not a Set, so nothing is queued | `rejection`: `reason`, and `field` or `value` | 1 |

`rejection.reason` is `nothingHeard`, `unrecognized`, `kilograms`, `fusedNumber` (numbers the
recognizer ran together), `ambiguous` (a number no word places, or words that may mean another Set),
`conflicting` (a `field` said twice, even as the same number, which reads as two Sets),
`outOfRange` (reps that are 0 or not whole, or a weight of 0 pounds),
`offLadderRPE` (the `value` heard is not an RPE), or `nothingToRepeat` ("same again" with no
earlier Set Log of the Exercise in the Session). A Dictation that listened, rather than read a
transcript, may also be `microphoneDenied`, `speechUnavailable`, or `listeningFailed`. A rejected
`say` prints its report, then a `spoken_set_rejected` error.

The grammar, as the tests in `Tests/Unit/SpokenSetTests.swift` pin it. A number is a value only
where a word next to it, or the phrase around it, says which, never by its place in the transcript.

- "for", "x", "by", and "times" put the weight before them and the reps after them ("185 for 5"),
  and said first they label the reps ("for 5"). "four" between a weight and a number is "for" too
  ("185 four 5"), and so is "per" after bodyweight or a weight heavier than the reps
  ("95 pounds per 6"). "25 per 30" is `ambiguous`. "or" between numbers is always `ambiguous`:
  "225 or 3" may be "225 for 3", and "20 or 25 reps" is a range.
- "pounds", "pound", "lbs", and "lb" label the number before them as the weight, as "£" does the
  number after it, even after "at" ("12 reps at 10 pounds"). "reps" labels the number before or
  after it ("8 reps", "reps 8"). "with" labels bodyweight or a number off the RPE ladder after it
  as the weight, "pounds" after it or not ("5 reps with 185 pounds"), and is filler anywhere else,
  so "for 5 with 8" is `ambiguous`.
- "RPE", "rp", "r p e", "RTE", "RTD", "RTV", and "@" label the number after them as the RPE, and
  "RPE" labels the number before it too ("8 RPE"). After "at", a number on the RPE ladder is the RPE
  ("at 8"), and bodyweight or any other number is the weight ("8 reps at 12").
- Right after a whole weight for reps, "and", "of", or "add" before a number is the "at" the
  recognizer mishears, and the number after it is never read: "185 for 5 and 8" is `missingValues`
  with the RPE missing, because "185 for 5 and 5" may be five Sets of five.
- A transcript that ends on "and", "and a", or "point" right after a number had its half or decimal
  cut off, so that value is missing: "at 8 and a" is `missingValues` with the RPE missing. A rep
  count is whole, so after one it is the RPE that is missing ("185 for 5 and").
- A value said twice is `conflicting`, even as the same number: "185 for 5 for 5" and "185 for 5
  reps, 5 reps".
- A Spoken Set holds any weight and rep count the card accepts: "4 for 5", "5 by 5", "135 for 45",
  and "187.55 for 5" each read as said. Reps that are 0 or not whole, or a weight of 0 pounds, is
  `outOfRange` ("135 for 0", "315 for 19.5", "0 for 5"), because a Set with no load is bodyweight
  and a Set not done is Skipped.
- A number no word places is `ambiguous`, never filled into a free value: "185, 5, 8", "5 at 8",
  "for 5, 8", and "eight" alone.
- Number words read as athletes say them: "one thirty five", "four oh five", "hundred eighty five",
  "eight and a half", "8 1/2", "8½", "one eighty seven point five", and a clock-style "1:35" for 135.
  "ate" is 8, and "to" or "too" is 2 only where a number is asked for. Number words in a row that
  make no one number, as "nine five", are `ambiguous`. A tens word and a unit after it are always
  one number, so "forty four five" is 44 and an unplaced 5, `ambiguous`.
- A number whose whole part has four or more digits is `fusedNumber`, never a weight: the recognizer
  wrote "40542" for "four oh five for two".
- A rep count written as two digits right after "for", with no "reps" after it and no RPE said, is
  `ambiguous` when its second digit is 6 to 9: "135 for 19" may be "135 for 1 at 9". "135 for 19
  reps", "135 for 15", and "45 for 10" log.
- "bodyweight", "body weight", and "BW" are the BW weight.
- "same again", "same", "same as last", "same as before", "do the same", "repeat", and "again" log
  the Exercise's nearest earlier Set Log in the Session. A command acts on this Set alone, so one
  that names a Set or Session, as "skip set one", "same as set one", and "same as last time" do, is
  `ambiguous`. Any other word in a command, as "same weight", is `unrecognized`.
- Filler such as "um", "okay", "please", "thanks", "yeah", "I", "just", "hit", "did", and "got" is
  dropped. Any other word, or a symbol such as "%", "+", or the minus of "135 for -5", rejects the
  transcript rather than being skipped.

```console
$ workout say w1d1.e0.s0 "RPE 9" | jq -c '{outcome, missing}'
{"outcome":"missingValues","missing":["weight"]}
$ workout say w1d1.e0.s0 "185 for 5 at 8" | jq -c '{outcome, setLog}'
{"outcome":"logged","setLog":"185x5@8"}
$ workout say w1d1.e0.s1 "at 9" | jq -c '{outcome, setLog}'     # the card's estimate, at the RPE said
{"outcome":"logged","setLog":"180x5@9"}
```

## Recordings

`hear` is `say` with Apple's on-device speech-to-text in front of it. It reads an audio file
through the model, configuration, and transcript mapping the Active Set Card's mic uses
(`Sources/WorkoutTracker/Session/OnDeviceSpeech.swift`): SpeechTranscriber with alternatives for
en-US, or DictationTranscriber where the Mac has no SpeechTranscriber. Then it hands every
transcript, most likely first, to `dictate`, which writes under the same Dictation write policy
as the locked phone. `candidates` is that list; `heard` is its first entry.

```console
$ say -o set.aiff "185 for 5 at 8"
$ workout hear w1d1.e0.s0 set.aiff | jq -c '{candidates, outcome, setLog}'
{"candidates":["185 for 5 at 8.","185 for five at 8.","185 for 5 and 8.","185 for 5 at eight."],"outcome":"logged","setLog":"185x5@8"}
```

It needs macOS 26 or later on a Mac that runs SpeechAnalyzer. The first run downloads the en-US
speech assets from Apple, free and with no account, and prints each whole percent to stderr as
`{"installingSpeechAssets":{"percent":42}}`. A recording with no speech in it is `rejected` as
`nothingHeard`. A path that is not an audio file is `unreadable_recording` (exit 1), a model that
fails partway through is `listening_failed` (exit 3), and a Mac without the model, or whose assets
would not install, is `speech_unavailable` (exit 69). `scripts/prove-dictation.sh` speaks a table
of phrases in two macOS voices, runs each through `hear`, flushes, and prints what landed in the
Sheet.

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
