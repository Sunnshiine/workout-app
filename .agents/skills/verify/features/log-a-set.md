# Log a set

Log a set lets the athlete record the active set's weight, reps, and RPE from the session stage, advances the card to the next set, marks the set on the exercise branch, and queues a write to the Sheet.

## Sub-features

- `log-adjust` changes weight with the pill steppers or the keyboard, and reps or RPE with the pickers.
- `log-submit` logs the active set and advances to the next one.
- `log-branch` shows the logged set as a dot on the exercise branch with its result.
- `log-pending` queues the write and shows it as unsynced in the header.
- `log-skip` skips the active set with a long press on the log button.
- `log-history` opens the exercise history sheet from the last-performed line.

## How to get to it (user POV)

- Open the app with a Current Session that has pending sets. The stage shows the first pending exercise and its active set card.
- From Block Overview, tap a session tile to open that session's stage.
- From the queue sheet, tap an exercise row to jump to its active set.

## Driving it with verify.sh

Preconditions:

- `verify.sh launch session` landed on Back Squat with `find session-remaining-count` reading `5 Sets left` and a `Set 1 of 3` static text.
- `verify.sh doctor` prints only `ok` lines.

- **Baseline.** Capture the stage. Run `verify.sh shot 01-before`. The tree has `AXButton  weight-pill  Weight, 237.5` and `AXButton  log-active-set-button  Log 237.5 × 5 @6` (RPE 6 is the prescribed default).
- **Pick RPE.** Tap RPE 7. Run `verify.sh tap --id rpe-7`. `verify.sh find log-active-set-button` now reads `Log 237.5 × 5 @7`. Run `verify.sh tap --id rpe-6` to return so the rest of the recipe matches.
- **Step weight.** Tap the increment pill. Run `verify.sh tap --id weight-increment`. `verify.sh find weight-pill` reads a higher weight and the log button label follows it. Tap `weight-decrement` to return.
- **Keyboard weight.** Tap the pill, clear it, type. Run `verify.sh tap --id weight-pill`, then `verify.sh axe key 42` five times (backspace), then `verify.sh type 245`, then `verify.sh tap --id weight-keyboard-done`. While editing the tree shows `AXTextField  weight-pill` valued `245`; after Done, `find weight-pill` reads `Weight, 245` and the log button reads `Log 245 × 5 @6`.
- **Log.** Tap the log button. Run `verify.sh tap --id log-active-set-button`. The tree gains `AXButton  Set 1, 237.5x5@6` on the branch, `Set 2 of 3` replaces `Set 1 of 3`, and `session-remaining-count` reads `4 Sets left`.
- **Side effect.** Confirm the queued write. `verify.sh tree | grep "Sync status"` prints `Sync status: 1 unsynced`. For the stored value, run the same log through the CLI (`cli-headless.md`) or `swift test --filter ActiveSetFocusManagerTests`.
- **Skip.** Long press the log button. Run `verify.sh hold log-active-set-button`. The branch gains `Set 2, skip` and the card reads `Set 3 of 3`.
- **History.** Tap the last-performed line. Run `verify.sh tap --label "Block 26 · W4 D3 — 245x5@6, 255x5@7"`. A sheet titled `Exercise History · last 5` lists `Block 26` and `Block 25`.
- **Proof.** Run `verify.sh shot 02-after-log`. It prints the lines that changed since `01-before`. Quote the `Set 1, 237.5x5@6`, `Set 2 of 3`, and `Sync status` lines. Then run `verify.sh sheet` and Read it. Cell 1 shows `Set 1 of 3` at 237.5 with no branch leaf filled. Cell 2 shows the `1 unsynced` pill, the first leaf filled, and the rest pill at the bottom edge. A cell 2 still reading `Set 1 of 3` means the shot caught the transition, so take it again.

## Gotchas

- Focusing the weight field keeps its value and typed digits append (`237.5` then `245` became `237.5245`). Backspace it clear before typing.
- The log button label carries the current pickers (`Log 237.5 × 5 @6`, with a multiplication sign). Assert on the exact label after each picker tap, not before.
- Load suggestion moves the next set's default weight (Set 2 opened at 252.5 after logging Set 1 at 237.5 @6). Do not assert the old weight after a log.
- `hold` needs about 1.2 s. A short `tap` on the log button logs the set instead of skipping it.
- With the keyboard up, the first tap on the log button dismisses the keyboard instead of logging (issue 536). Tap `weight-keyboard-done` first.
- The rest pill starts after a log and counts down. It is not proof of anything about the set.
- Fixture writes never reach Google. `Sync status: 1 unsynced` proves the queue, not the Sheet.
