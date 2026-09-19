# Headless CLI

The `workout` CLI runs the app's stores against a local workbook file and prints JSON, so store, queue, and sync behavior can be proven in milliseconds without a simulator.

## Sub-features

- `cli-init` seeds a scenario workbook and selects it through the onboarding path.
- `cli-inspect` prints the sync outcome, the Current Session, and any session with set addresses.
- `cli-log` logs a set and queues the write.
- `cli-flush` writes queued sets to the workbook and reports conflicts.
- `cli-sync` re-reads the workbook and reports the parsed state.

## How to get to it (user POV)

- Run `.build/debug/workout <command>` after `swift build --product workout`.
- Every command takes `--home <dir>`, else `$WORKOUT_HOME`, else `./.workout-cli`.

## Driving it with verify.sh

Preconditions:

- `.build/debug/workout` exists (`swift build --product workout`).
- `export WORKOUT_HOME=$(mktemp -d)` so the run owns its home.

- **Init.** Run `workout init --scenario fresh-block`. Exit 0, stdout names `"currentSession" : "w1d1"` and `"scenario" : "fresh-block"`.
- **Inspect.** Run `workout session`. The first exercise's first set is `"id" : "w1d1.e0.s0"` with `"state" : "pending"`.
- **Log.** Run `workout log w1d1.e0.s0 185x5@8`. Exit 0, `"pendingWriteCount" : 1`, the set's `"state" : "logged"` and `"setLog" : "185x5@8"`.
- **Flush.** Run `workout flush`. Exit 0, `"written" : 1`, `"remainingPendingWrites" : 0`, empty `conflictedWrites`.
- **Stored value.** Run `workout sheet --cell K15`. `"value" : "185x5@8"`.
- **Sync.** Run `workout sync` then `workout session w1d1`. On a clean run `sync` prints `"status" : "clear"` under `syncOutcome`. The same set reads `"state" : "logged"`, parsed back from the workbook.
- **Error shape.** Run `workout log w1d1.e0.s9 185x5@8; echo $?`. Stdout empty, stderr one JSON line with `"code":"unknown_set"` and candidates, exit 1.
- **Outcome shape.** Strip the `Day N` header cells with `jq '.tabs["Block 27"].cells |= with_entries(select(.value | test("^Day [0-9]+$") | not))' "$WORKOUT_HOME/workbook.json" > "$WORKOUT_HOME/wb.tmp" && mv "$WORKOUT_HOME/wb.tmp" "$WORKOUT_HOME/workbook.json"`, then run `workout sync; echo $?`. Exit 4 with `"status" : "parseWarnings"` under `syncOutcome`. A refused write exits 4 too and prints `"status" : "writesRefused"`, so the status is what tells them apart. Neither run needs its `messages` read.
- **Proof.** Save each command's stdout, stderr, and exit code under the evidence directory (`tee "$EVIDENCE/cli-flush.json"`).

## Gotchas

- `init` refuses a non-empty foreign directory (exit 3). Use a fresh `mktemp -d`.
- Settings live in `$WORKOUT_HOME/settings.json`. `init` resets them, and deleting the home deletes them.
- `log` twice enqueues twice. It is not idempotent, by design.
- `WORKOUT_NOW=2026-05-28T20:26:40Z` freezes `loggedAt` for stable assertions.
- A flush conflict exits 4 on every later run until the write is discarded. Read `conflictedWrites`, not the exit code alone. `syncOutcome.status` names which outcome ended the step; never string-match `messages`.
- The workbook is the fixture sheet, not Google. A green flush proves the queue and the write path, not the network.
