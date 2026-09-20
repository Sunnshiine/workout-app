# Log a set

Log a set lets the athlete record the active set's weight, reps, and RPE from the session stage, advances the card to the next set, marks the set on the exercise branch, and queues a write to the Sheet.

## Sub-features

- `log-adjust` changes weight with the pill steppers or the keyboard, and reps or RPE with the pickers.
- `log-submit` logs the active set and advances to the next one.
- `log-branch` shows each set as a leaf on the exercise branch with its result, and reopens a set from its leaf.
- `log-review` edits a logged set from its reopened card and saves when the card collapses.
- `log-pending` queues the write and shows it as unsynced in the header.
- `log-skip` skips the active set with a long press on the log button, and clears the skip from the set's More menu.
- `log-history` opens the exercise history sheet from the last-performed line, with a volume chart.

## How to get to it (user POV)

- Open the app with a Current Session that has pending sets. The stage shows the first pending exercise and its active set card.
- From Block Overview, tap a session tile to open that session's stage.
- From the queue sheet, tap an exercise row to jump to its active set.

## Driving it with verify.sh

Preconditions:

- `verify.sh launch session` landed on Back Squat with `find session-remaining-count` reading `5 Sets left` and a `Set 1 of 3` static text.

- **Baseline.** Capture the stage. Run `verify.sh shot 01-before`. The tree has `AXButton  weight-pill  Weight, 237.5` and `AXButton  log-active-set-button  Log 237.5 × 5 @6` (RPE 6 is the prescribed default).
- **History.** Tap the last-performed line. Run `verify.sh tap --label "Block 26 · W4 D3 — 245x5@6, 255x5@7"`. A half-height sheet titled `Back Squat` with `Exercise History · last 5` lists `Block 26` and `Block 25`. Run `verify.sh tap --id history-volume-toggle`. Its value turns `on` and `find history-volume-chart` answers. Drag the sheet away with `verify.sh axe swipe --start-x 200 --start-y 70 --end-x 200 --end-y 800 --duration 0.3`.
- **Pick RPE and reps.** Run `verify.sh tap --id rpe-7`. `verify.sh find log-active-set-button` reads `Log 237.5 × 5 @7`. Run `verify.sh tap --id rpe-6`, then `verify.sh tap --id reps-6`. The button reads `Log 237.5 × 6 @6`. Run `verify.sh tap --id reps-5` to return.
- **Step weight.** Run `verify.sh tap --id weight-increment`. `verify.sh find weight-pill` reads `Weight, 242.5` and the log button follows it. Run `verify.sh tap --id weight-decrement` to return.
- **Log.** Run `verify.sh tap --id log-active-set-button`, wait a second for the card to advance, then run `verify.sh shot 02-after-log`. The changed lines gain `AXButton  Set 1, 237.5x5@6` on the branch, `Set 2 of 3` replaces `Set 1 of 3`, `session-remaining-count` reads `4 Sets left`, the last-performed line becomes `Block 27 · W1 D1 — 237.5x5@6`, and `Sync status: 1 unsynced` appears. That last line is the queued write. For the stored value, run the same log through the CLI (`cli-headless.md`) or `swift test --filter WorkoutStoreLoggingTests`.
- **Keyboard weight.** Tap the pill, clear it, type. Run `verify.sh tap --id weight-pill`, then `verify.sh axe key 42` five times (backspace), then `verify.sh type 245`, then `verify.sh tap --id weight-keyboard-done`. While editing the tree shows `AXTextField  weight-pill` valued `245`. After Done, `find weight-pill` reads `Weight, 245` and the log button reads `Log 245 × 5 @7`.
- **Skip.** Long press the log button. Run `verify.sh hold log-active-set-button`. The branch gains `Set 2, skip`, the card reads `Set 3 of 3`, and the header reads `Sync status: 2 unsynced`.
- **Clear the skip.** Run `verify.sh tap --label "Set 2, skip"`. The card reads `Set 2 of 3` and `verify.sh find clear-logged-set-menu` answers, which it never does for a pending set. Run `verify.sh tap --id clear-logged-set-menu`, then `verify.sh tap --label Clear`. The leaf returns to `Set 2, 5 · RPE7` and `session-remaining-count` reads `4 Sets left`.
- **Review a logged set.** Run `verify.sh tap --label "Set 1, 237.5x5@6"`. The card reads `Set 1 of 3` with a `Collapse logged set` button, and `verify.sh find log-active-set-button` exits 1. Run `verify.sh tap --id rpe-7`, then `verify.sh tap --label "Collapse logged set"`. The leaf reads `Set 1, 237.5x5@7` and the unsynced count rises by one.
- **Proof.** Quote the `Set 1, 237.5x5@6`, `Set 2 of 3`, and `Sync status` lines from `02-after-log`. On the sheet, the `01-before` cell shows `Set 1 of 3` at 237.5 with no branch leaf filled. The `02-after-log` cell shows the `1 unsynced` pill, the first leaf filled, and the rest pill at the bottom edge. If that cell still reads `Set 1 of 3`, the shot caught the transition, so take it again.

## Gotchas

- Focusing the weight field keeps its value and typed digits append (`237.5` then `245` became `237.5245`). Backspace it clear before typing.
- A log replaces the last-performed line with this session's result, so **History** runs before **Log**. After a log, tap the new label.
- Load suggestion moves the next set's default weight (Set 2 opened at 252.5 after logging Set 1 at 237.5 @6). Assert the weight the card shows now, never the one before the log.
- With the keyboard up, the first tap on the log button dismisses the keyboard instead of logging (issue 536). Tap `weight-keyboard-done` first.
- Only a skipped set's card has `clear-logged-set-menu`. A logged set's card has no log button and no Clear.
