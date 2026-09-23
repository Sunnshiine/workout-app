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
- **History.** Tap the last-performed line. Run `verify.sh tap --label "Block 26 · W4 D3 — 245x5@6, 255x5@7"`. A half-height sheet titled `Back Squat` with `Exercise History · last 5` lists `Block 26` and `Block 25`. Run `verify.sh tap --id history-volume-toggle`. Its value turns `on` and `find history-volume-chart` answers. Run `verify.sh shot 02-history`. Dismiss the sheet with `verify.sh axe swipe --start-x 200 --start-y 70 --end-x 200 --end-y 800 --duration 0.3`, then confirm it closed with `verify.sh find history-volume-toggle` exiting 1. Every bullet below assumes it is gone.
- **Pick RPE and reps.** Run `verify.sh tap --id rpe-6.5`, the last RPE chip the rail draws. `verify.sh find log-active-set-button` reads `Log 237.5 × 5 @6.5`. Run `verify.sh tap --id rpe-6`, then `verify.sh tap --id reps-6`. The button reads `Log 237.5 × 6 @6`. Run `verify.sh tap --id reps-5` to return.
- **Step weight.** Run `verify.sh tap --id weight-increment`. `verify.sh find weight-pill` reads `Weight, 242.5` and the log button follows it. Run `verify.sh tap --id weight-decrement` to return.
- **Log.** Run `verify.sh tap --id log-active-set-button`, wait a second, then run `verify.sh shot 03-after-log`. Its changed lines are measured against `02-history`, so they also carry that sheet's teardown; read the log on its own with `verify.sh diff 01-before 03-after-log`. It gains `AXButton  Set 1, 237.5x5@6` on the branch, `Set 2 of 3` replaces `Set 1 of 3`, `session-remaining-count` reads `4 Sets left`, the last-performed line becomes `Block 27 · W1 D1 — 237.5x5@6`, and `Sync status: 1 unsynced` appears. That last line is the queued write. For the stored value, run the same log through the CLI (`cli-headless.md`) or `swift test --filter WorkoutStoreLoggingTests`.
- **Keyboard weight.** Tap the pill, clear it, type. Run `verify.sh tap --id weight-pill`, then `verify.sh axe key 42` five times (backspace), then `verify.sh type 245`, then `verify.sh tap --id weight-keyboard-done`. While editing the tree shows `AXTextField  weight-pill` valued `245`. After Done, `find weight-pill` reads `Weight, 245` and the log button reads `Log 245 × 5 @7`.
- **Skip.** Long press the log button. Run `verify.sh hold log-active-set-button`. The branch gains `Set 2, skip`, the card reads `Set 3 of 3`, and the header reads `Sync status: 2 unsynced`.
- **Clear the skip.** Run `verify.sh tap --label "Set 2, skip"`. The card reads `Set 2 of 3` and `verify.sh find clear-logged-set-menu` answers, which it never does for a pending set. Run `verify.sh tap --id clear-logged-set-menu`, then `verify.sh tap --label Clear`. The leaf returns to `Set 2, 5 · RPE7` and `session-remaining-count` reads `4 Sets left`.
- **Review a logged set.** Run `verify.sh tap --label "Set 1, 237.5x5@6"`. The card reads `Set 1 of 3` with a `Collapse logged set` button, and `verify.sh find log-active-set-button` exits 1. Run `verify.sh shot 04-review` while the card is open, because collapsing it is what the next tap does. Run `verify.sh tap --id rpe-6.5`, then `verify.sh tap --label "Collapse logged set"`. The leaf reads `Set 1, 237.5x5@6.5` and the unsynced count rises by one, 3 to 4.
- **Proof.** Quote the `Set 1, 237.5x5@6`, `Set 2 of 3`, and `Sync status` lines from `03-after-log`. On the sheet, the `01-before` cell shows `Set 1 of 3` at 237.5, all three branch leaves drawn as empty outlines, and the green `Log 237.5 × 5 @6` button under the pickers. The `02-history` cell shows the stage dimmed to grey behind the sheet and the volume chart drawn as a three-point line rising left to right, which `find history-volume-chart` on its own cannot prove. The `03-after-log` cell shows the `1 unsynced` pill above the header, the first leaf filled solid, and the rest pill on the bottom edge at y 816 of 874. The `04-review` cell shows the reopened card with no log button at all, ending at the reps and RPE rows, and `Collapse logged set` rendered as a 15x8 chevron in the card's top right corner. If the `03-after-log` cell still reads `Set 1 of 3`, the log did not land, so read its tree for `Sync status` and `find log-active-set-button` before taking another shot.

## Gotchas

- Focusing the weight field keeps its value and typed digits append (`237.5` then `245` became `237.5245`). Backspace it clear before typing.
- A log replaces the last-performed line with this session's result, so **History** runs before **Log**. After a log, tap the new label.
- The history sheet opens at its medium detent, grabber at y 411, so the dismissing swipe starts on the dimming view above the sheet rather than on the sheet. It closes it anyway. Assert `find history-volume-toggle` exits 1 instead of reasoning from the geometry.
- Load suggestion moves the next set's default weight (Set 2 opened at 252.5 after logging Set 1 at 237.5 @6). Assert the weight the card shows now, never the one before the log.
- With the keyboard up, the first tap on the log button dismisses the keyboard instead of logging (issue 536). Tap `weight-keyboard-done` first.
- Only a skipped set's card has `clear-logged-set-menu`. A logged set's card has no log button and no Clear.
- The Reps and RPE rails draw only about three chips at a time and recentre on the selection, so most chips sit outside the drawn track. `tree` still lists an outside chip and `find` still reports it with no warning, because both measure against the 402-point screen rather than the track. `tap --id` then taps its centre, reports success, exits 0, and changes nothing. Tap only a chip the rail draws (with `rpe-6` selected that is `rpe-5` through `rpe-6.5`), step one chip at a time since each tap slides the next one into the track, and read the log button afterwards rather than trusting the exit code.
