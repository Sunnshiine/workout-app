# Session completion

When every set in the session is logged or skipped the stage becomes the completion stage, which summarizes the session, lists open exercises from earlier sessions, and offers Move On to the next session with a celebration.

## Sub-features

- `complete-summary` shows `Session complete` with the done count.
- `complete-open-exercises` lists exercises with pending sets from earlier sessions and opens their source session.
- `complete-move-on` advances the Current Session and shows the celebration.
- `complete-celebration-dismiss` returns to the next session or the Block grid.

## How to get to it (user POV)

- Log or skip every set in the Current Session.
- Open the app with a completed Current Session (`completed-open-exercises` fixture).
- Tap Move On inside the queue sheet (`queue-move-on-button`).

## Driving it with verify.sh

Preconditions:

- `verify.sh launch completed-open-exercises` landed on `Session complete` with `session-remaining-count` reading `0 Sets left`.
- For the celebration, `verify.sh launch partial-block` and follow the terminal Move On path.

- **Summary.** Capture the stage. Run `verify.sh shot complete`. The tree has `Session complete`, `1 set done across 1 exercise`, `Open Exercises`, and `move-on-button`.
- **Open exercise.** Tap the open Back Squat row. Run `verify.sh tap --label "Back Squat, 1 pending set, W1 D1"`. `go-back-current-session-button` appears and `Back Squat` is on the stage.
- **Move on with celebration.** From `partial-block`, run `verify.sh tap --id session-tile-W4-D1`, `verify.sh tap --id make-current-session-button`, `verify.sh tap --id stage-queue-button`, `verify.sh tap --id queue-move-on-button`. `find move-on-celebration` is labeled `Week 4, Day 1` and its value contains `1 Sets, 1 Exercises, 1 Left`.
- **Dismiss.** Run `verify.sh tap --id move-on-celebration-continue`. The `Block 27` heading returns, `move-on-celebration` is gone, and `session-tile-W4-D2` is in the tree.
- **Proof.** Shoot the celebration and the grid after it. Quote the celebration label and value lines.

## Gotchas

- Every launch passes `-UITEST_DISABLE_CELEBRATION_BLOOM`, which removes the bloom animation but not the celebration view. The `move-on-celebration` group still appears.
- Developer Tools has `developer-tools-force-celebration-button`. It is a debug shortcut and does not prove Move On.
- Reaching completion by logging every set through the `session` fixture takes 12 logs across four exercises. Prefer the fixture for the completion stage and use logging only to prove the transition itself.
