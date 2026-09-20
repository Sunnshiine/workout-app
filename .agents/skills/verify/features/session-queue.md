# Session queue

The queue bar at the foot of the session stage jumps to the next exercise, and its sheet lists every exercise in the session with its state, lets the athlete jump to any exercise, and pairs two exercises into a superset.

## Sub-features

- `queue-up-next` jumps to the next unfinished exercise from the bar's `Up next` button, without opening the sheet.
- `queue-open` opens the sheet from the bar's queue button, whose label counts finished exercises (`1 of 8`).
- `queue-list` lists every exercise, marks the one on stage `Now`, and disables a finished one.
- `queue-jump` opens an exercise's active set from its row.
- `queue-pair` starts pairing from an exercise's pair button and cancels or completes it.

## How to get to it (user POV)

- Tap the queue button at the bottom right of the session stage, or `Up next` at the bottom left.
- The completion stage keeps the same queue button.

## Driving it with verify.sh

Preconditions:

- `verify.sh launch long-session` landed on Back Squat and `verify.sh find stage-queue-button` reads `1 of 8`.

- **Open.** Tap the queue button. Run `verify.sh tap --id stage-queue-button`. The tree has `This Session`, `stage-queue-row-exercise-0` labeled `Primer Row`, and `stage-queue-row-exercise-1` labeled `Back Squat, Now`. `verify.sh axe describe-ui` reports `enabled` false for the finished `Primer Row` and true for every other row.
- **List.** Scroll for the tail. Run `verify.sh shot queue-top`, `verify.sh swipe up`, `verify.sh shot queue-tail`. The second shot prints `+ AXButton  stage-queue-row-exercise-7  Farmer Carry`.
- **Jump.** Tap the last row. Run `verify.sh tap --id stage-queue-row-exercise-7`. The sheet closes, `find stage-exercise-name` reads `Farmer Carry`, and the cue `Tall posture.` is in the tree.
- **Up next.** Launch `session`. `verify.sh find stage-queue-button` reads `0 of 2` and `find stage-up-next` reads `Up next ·, 2-3:1:0 BB RDL`. Run `verify.sh tap --id stage-up-next`. `find stage-exercise-name` reads `BB RDL` and the button reads `Up next ·, Back Squat`. Tap it again to return.
- **Pair.** Open the queue and tap the pair button on exercise 0. Run `verify.sh tap --id stage-queue-button`, then `verify.sh tap --id stage-queue-pair-exercise-0`. The sheet reads `Pick a partner` with `stage-queue-cancel-pairing`, and the pair buttons leave.
- **Cancel pairing.** Run `verify.sh tap --id stage-queue-cancel-pairing`. The sheet reads `This Session` again, `stage-queue-pair-exercise-0` is back, and `verify.sh find stage-queue-row-superset-0` exits 1.
- **Complete pairing.** Run `verify.sh tap --id stage-queue-pair-exercise-0`, then `verify.sh tap --id stage-queue-row-exercise-1`, and wait a second. One row, `stage-queue-row-superset-0` labeled `Back Squat + BB RDL, Now`, replaces both, `verify.sh find stage-queue-row-exercise-1` exits 1, and the queue button reads `0 of 1`. Run `verify.sh tap --id stage-queue-row-superset-0`. The sheet closes and the stage shows `superset-partner-name` labeled `& BB RDL` under `Back Squat`.

## Gotchas

- The sheet is half height, so the last `long-session` rows start off-screen.
- A row carries the coach's full exercise name (`2-3:1:0 BB RDL`). The stage strips the tempo prefix (`BB RDL`).
- The superset lands about a quarter second after the partner tap. Read the tree before that and the two rows are still there.
- The sheet's `queue-move-on-button` and its `Open Exercises` list belong to `session-completion.md`.
