# Session queue

The queue bar at the foot of the session stage jumps to the next exercise, and its sheet lists every exercise in the session with its state, lets the athlete jump to any exercise, and pairs two exercises into a superset.

## Sub-features

- `queue-up-next` jumps to the next unfinished exercise from the bar's `Up next` button, without opening the sheet.
- `queue-open` opens the sheet from the bar's queue button, a `square.stack` glyph labeled `Queue` whose value names the stage's position in the queue (`2 of 8`).
- `queue-list` lists every exercise, marks the one on stage `Now`, and greys a finished one.
- `queue-revisit` reopens a finished exercise from its row with its first logged set open for review, so a set can be fixed without the Sheet. A finished superset's row stays disabled.
- `queue-jump` opens an exercise's active set from its row.
- `queue-pair` starts pairing from the header's Superset button and cancels or completes it.
- `queue-unlink` splits a superset back into its exercises from the superset row's trailing glyph.

## How to get to it (user POV)

- Tap the queue button at the bottom right of the session stage, or `Up next` at the bottom left.
- The completion stage keeps the same queue button.

## Driving it with verify.sh

Preconditions:

- `verify.sh launch long-session` landed on Back Squat and `verify.sh find stage-queue-button` reads `Queue` valued `2 of 8`.

- **Open.** Tap the queue button. Run `verify.sh tap --id stage-queue-button`. The tree has `This Session`, `stage-queue-row-exercise-0` labeled `Primer Row`, and `stage-queue-row-exercise-1` labeled `Back Squat, Now`. `Primer Row` is finished, so its title is grey.
- **Revisit.** Run `verify.sh tap --id stage-queue-row-exercise-0`, wait a second, then `verify.sh shot queue-revisit`. The sheet closes, `find stage-exercise-name` reads `Primer Row`, the card reads `Set 1 of 1` and `find logged-set-capsule` reads `95x8@6`. Run `verify.sh tap --label "Set 1, 95x8@6"` to close the review, and `find stage-exercise-name` returns to `Back Squat`. Reopen the sheet with `verify.sh tap --id stage-queue-button` for the next bullet.
- **List.** Scroll for the tail. Run `verify.sh shot queue-top`, `verify.sh swipe up`, `verify.sh shot queue-tail`. The second shot prints `+ AXButton  stage-queue-row-exercise-7  Farmer Carry`.
- **Jump.** Tap the last row. Run `verify.sh tap --id stage-queue-row-exercise-7`. The sheet closes, `find stage-exercise-name` reads `Farmer Carry`, and the cue `Tall posture.` is in the tree.
- **Up next.** Relaunch on the smaller fixture. Run `verify.sh stop`, then `verify.sh launch session`. `verify.sh find stage-queue-button` reads `Queue` valued `1 of 2` and `find stage-up-next` reads `Up next, BB RDL`. Run `verify.sh tap --id stage-up-next`. `find stage-exercise-name` reads `BB RDL` and the button reads `Up next, Back Squat`. Tap it again to return.
- **Pair.** Open the queue and tap the header's Superset button. Run `verify.sh tap --id stage-queue-button`, then `verify.sh tap --id stage-queue-superset`. The title still reads `This Session`, `stage-queue-cancel-pairing` labeled `Cancel Superset` takes the button's place, and `verify.sh find stage-queue-superset` exits 1.
- **Cancel pairing.** Run `verify.sh tap --id stage-queue-cancel-pairing`. `stage-queue-superset` is back, `verify.sh find stage-queue-cancel-pairing` exits 1, and `verify.sh find stage-queue-row-superset-0` exits 1.
- **Complete pairing.** Run `verify.sh tap --id stage-queue-superset`, then `verify.sh shot queue-pairing`, then `verify.sh tap --id stage-queue-row-exercise-1`, and wait a second. The sheet closes on its own and the stage shows `superset-partner-name` labeled `& BB RDL` under `Back Squat`. `verify.sh find queue-move-on-button` exits 1. Reopen the queue with `verify.sh tap --id stage-queue-button` and run `verify.sh shot superset-row`. One row, `stage-queue-row-superset-0` labeled `Superset, Back Squat + BB RDL, Now`, replaces both, `verify.sh find stage-queue-row-exercise-1` exits 1, and the queue button reads `Queue` valued `1 of 1`. The changed lines also drop `stage-up-next` from the stage, because nothing is queued behind a single item.
- **Unlink.** The queue is still open on the superset from the last step. Run `verify.sh tap --id stage-queue-unlink-superset-0` (labeled `Unlink Superset`), then `verify.sh shot queue-unlinked`. `stage-queue-row-exercise-0` and `stage-queue-row-exercise-1` are back, `verify.sh find stage-queue-row-superset-0` exits 1, and the queue button reads `Queue` valued `1 of 2`.
- **Proof.** On the sheet, `queue-top` and `queue-tail` are the half-height sheet either side of one `swipe up`. The top cell clips `Cable Crunch` at the bottom edge and the tail cell clips `Back Squat` at the top, so neither alone holds all eight rows, and `Primer Row` is the one grey row, which is what finished looks like. `queue-revisit` shows that row's exercise back on stage with its logged set open. `queue-pairing` and `superset-row` are the pair that proves the merge. Two rows carrying three and two set pips become one row carrying five under `Back Squat + BB RDL`, and the title stays `This Session`. The sheet closes after the partner tap, so no `Move On` can be tapped by accident. In `queue-pairing` the outlined capsule marks only the row the pairing started from, the X sits where the Superset button was, and each eligible row carries the budded stem. In `superset-row` the joined stem leads the row and the grey split stem trails it.

## Gotchas

- The sheet is half height, so the last `long-session` rows start off-screen.
- Rows, `Up next`, and the stage all strip the coach's tempo prefix, so `2-3:1:0 BB RDL` reads `BB RDL`.
- The superset lands about a quarter second after the partner tap, and the sheet closes then. Read the tree before that and the sheet still shows the two rows.
- The sheet's `queue-move-on-button` and its `Open Exercises` list belong to `session-completion.md`.
