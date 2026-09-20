# Session queue

The session queue sheet lists every exercise in the session with its state, lets the athlete jump to any exercise, pair two exercises into a superset, and move on from the session.

## Sub-features

- `queue-open` opens the sheet from the stage's queue button, whose label counts progress (`1 of 8`).
- `queue-list` lists every exercise with `Now`, done, or pending state.
- `queue-jump` opens an exercise's active set from its row.
- `queue-pair` starts pairing from an exercise's pair button and cancels or completes it.
- `queue-move-on` moves on from the session through the queue's Move On button.

## How to get to it (user POV)

- Tap the queue button at the bottom right of the session stage.
- The completion stage keeps the same queue button.

## Driving it with verify.sh

Preconditions:

- `verify.sh launch long-session` for the eight-exercise list, or `verify.sh launch session` for pairing.
- `verify.sh find stage-queue-button` reads `1 of 8` (long-session) or `1 of 4` (session).

- **Open.** Tap the queue button. Run `verify.sh tap --id stage-queue-button`. The tree has `This Session` and `stage-queue-row-exercise-0` labeled `Back Squat, Now`, which is disabled.
- **List.** Scroll for the tail. Run `verify.sh shot queue-top`, `verify.sh swipe up`, `verify.sh shot queue-tail`. The second shot prints `+ AXButton  stage-queue-row-exercise-7  Farmer Carry` (long-session).
- **Jump.** Tap the last row. Run `verify.sh tap --id stage-queue-row-exercise-7`. The sheet closes, `find stage-exercise-name` reads `Farmer Carry`, and the cue `Tall posture.` is in the tree.
- **Pair.** From the session fixture, open the queue and tap the pair button on exercise 0. Run `verify.sh tap --id stage-queue-pair-exercise-0`. The sheet reads `Pick a partner`.
- **Cancel pairing.** Run `verify.sh tap --id stage-queue-cancel-pairing`. The sheet reads `This Session` again, `stage-queue-pair-exercise-0` is back, and `verify.sh find stage-queue-row-superset-0` exits 1.
- **Complete pairing.** Run `verify.sh tap --id stage-queue-pair-exercise-0` then tap a partner row such as `stage-queue-row-exercise-1`. The list gains `stage-queue-row-superset-0` and the stage shows `superset-partner-name`.
- **Proof.** Run `verify.sh shot queue-open` with the sheet up and quote the row lines.

## Gotchas

- The sheet is a half-height presentation. Rows below the fold are out of `tree`, and `find` reports them off-screen. `swipe up` before tapping them.
- The `Now` row is disabled by design. Tapping it is not a jump.
- Pairing is not persisted across relaunch in fixture mode. Do not prove it by relaunching.
- The Move On button inside the queue is `queue-move-on-button` and belongs to `session-completion.md`.
