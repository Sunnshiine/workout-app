# Headless CLI

The `workout` CLI runs the app's stores against a local workbook file and prints JSON, so store, queue, and sync behavior can be proven in milliseconds without a simulator.

## Sub-features

- `cli-init` seeds a scenario workbook and selects it through the onboarding path.
- `cli-status` prints the sync outcome, the Current and Viewed Session, the pending write count, and the session index.
- `cli-session` prints any session with set addresses.
- `cli-log` logs a set and `cli-skip` skips one. Both queue a write.
- `cli-flush` writes queued sets to the workbook and reports conflicts.
- `cli-sheet` reads one workbook cell, or every non-empty cell.
- `cli-sync` re-reads the workbook and reports the parsed state, optionally viewing another session.

## How to get to it (user POV)

- Run `.build/debug/workout <command>` after `swift build --product workout`.
- Every command takes `--home <dir>`, else `$WORKOUT_HOME`, else `./.workout-cli`.

## Driving it with verify.sh

Preconditions:

- `.build/debug/workout` exists and is first on `PATH`, and `WORKOUT_HOME` is a fresh `mktemp -d`.

- **Init.** Run `workout init --scenario fresh-block`. Exit 0, stdout names `"currentSession" : "w1d1"` and `"scenario" : "fresh-block"`.
- **Status.** Run `workout status`. Exit 0, `"pendingWriteCount" : 0`, `"viewedSession" : "w1d1"`, `"canMoveOn" : true`, and five entries under `sessions`.
- **Session.** Run `workout session`. The first exercise's first set is `"id" : "w1d1.e0.s0"` with `"state" : "pending"`.
- **Log.** Run `workout log w1d1.e0.s0 185x5@8`. Exit 0, `"pendingWriteCount" : 1`, the set's `"state" : "logged"` and `"setLog" : "185x5@8"`.
- **Skip.** Run `workout skip w1d1.e0.s1`. Exit 0, `"pendingWriteCount" : 2`, that set's `"state" : "skipped"`.
- **Flush.** Run `workout flush`. Exit 0, `"written" : 2`, `"remainingPendingWrites" : 0`, empty `conflictedWrites`.
- **Stored value.** Run `workout sheet --cell K15`. `"value" : "185x5@8, skip"`. Without `--cell` it prints every non-empty cell, and `--tab` picks the tab.
- **Sync.** Run `workout sync --viewing w2d3`. `"status" : "clear"` under `syncOutcome`, `"viewedSession" : "w2d3"`, and `"currentSession" : "w1d1"`. Then `workout session w1d1` reads the two sets back as `"logged"` and `"skipped"`, parsed from the workbook.
- **Error shape.** Run `workout log w1d1.e0.s9 185x5@8; echo $?`. Stdout empty, stderr one JSON line with `"code":"unknown_set"` and candidates, exit 1.
- **Outcome shape.** Strip the `Day N` header cells with `jq '.tabs["Block 27"].cells |= with_entries(select(.value | test("^Day [0-9]+$") | not))' "$WORKOUT_HOME/workbook.json" > "$WORKOUT_HOME/wb.tmp" && mv "$WORKOUT_HOME/wb.tmp" "$WORKOUT_HOME/workbook.json"`, then run `workout sync; echo $?`. Exit 4 with `"status" : "parseWarnings"` under `syncOutcome` and `"code":"sync_conflict"` on stderr. A refused write exits 4 too and prints `"status" : "writesRefused"`, so the status is what tells them apart.
- **Proof.** A CLI drive has no `launch` to name its evidence directory. Run `mkdir -p .build/verify/evidence/<run>` and save each command's stdout, stderr, and exit code there.

## Gotchas

- `init` refuses a non-empty foreign directory (exit 3).
- Settings live in `$WORKOUT_HOME/settings.json`. `init` resets them, and deleting the home deletes them.
- `log` twice enqueues twice. It is not idempotent, by design.
- `WORKOUT_NOW=2026-05-28T20:26:40Z` freezes `loggedAt` for stable assertions.
- A flush conflict exits 4 on every later run, and no verb discards the write. Read `conflictedWrites` and `syncOutcome.status`, never `messages`, and start a fresh home to go on.
