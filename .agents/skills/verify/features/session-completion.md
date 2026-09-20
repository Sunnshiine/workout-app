# Session completion

When every set in the session is logged or skipped the stage becomes the completion stage, which summarizes the session and lists open exercises. Move On advances to the next session with a celebration, and it is offered from any session that has a later one, finished or not.

## Sub-features

- `complete-summary` shows `Session complete` with the done count.
- `complete-open-exercises` lists exercises with pending sets from earlier days of the Current Session's week, on the completion stage and in the queue sheet, and opens their source session.
- `complete-move-on` shows the celebration from the stage's Move On or the queue sheet's.
- `complete-celebration-dismiss` continues to the next uploaded session, or to the Block grid when none is left.

## How to get to it (user POV)

- Log or skip every set in the Current Session.
- Open the app with a completed Current Session (`completed-open-exercises` fixture).
- Tap Move On inside the queue sheet (`queue-move-on-button`) of any Current Session with a later session.

## Driving it with verify.sh

Preconditions:

- `verify.sh launch completed-open-exercises` landed on `Session complete` with `session-remaining-count` reading `0 Sets left`.

- **Summary.** Capture the stage. Run `verify.sh shot complete`. The tree has `Session complete`, `1 set done across 1 exercise`, `Open Exercises`, `move-on-button`, and `stage-queue-button` reading `1 of 1`.
- **Open exercise.** Tap the open Back Squat row. Run `verify.sh tap --label "Back Squat, 1 pending set, W1 D1"`. `go-back-current-session-button` appears and `Back Squat` is on the stage. Run `verify.sh tap --id go-back-current-session-button` to return.
- **Open exercises in the queue.** Run `verify.sh tap --id stage-queue-button`. The sheet repeats `Open Exercises` with the same row above `queue-move-on-button`. Close it with `verify.sh tap -x 200 -y 150`.
- **Move on from the stage.** Run `verify.sh tap --id move-on-button`. `find move-on-celebration` is labeled `Week 1, Day 2` and its value ends `1 Sets, 1 Exercises, 0 Left`.
- **Continue to the next session.** Run `verify.sh tap --id move-on-celebration-continue`. `verify.sh find move-on-celebration` exits 1, `find session-location-button` reads `Open Block Overview for Week 1, Day 3`, and `find stage-exercise-name` reads `Deadlift`.
- **Move on early.** Launch `session`. Run `verify.sh tap --id stage-queue-button`, then `verify.sh tap --id queue-move-on-button`. `find move-on-celebration` is labeled `Week 1, Day 1` and its value ends `5 Sets, 2 Exercises, 5 Left`. Continue lands on `Bench Press`.
- **Continue to the grid.** Launch `partial-block`. Run `verify.sh tap --id session-tile-W4-D1`, `verify.sh tap --id make-current-session-button`, `verify.sh tap --id stage-queue-button`, `verify.sh tap --id queue-move-on-button`. `find move-on-celebration` is labeled `Week 4, Day 1` and its value ends `1 Sets, 1 Exercises, 1 Left`. Run `verify.sh tap --id move-on-celebration-continue`. The `Block 27` heading returns, `verify.sh find move-on-celebration` exits 1, and `session-tile-W4-D2` reads `Not uploaded`.

## Gotchas

- The celebration's value opens with a coach line picked at random. Assert its label and the `Sets, Exercises, Left` tail.
- With the queue sheet up, the open exercise's label matches twice. Close the sheet before `tap --label`.
- Prove Move On through a Move On button. Developer Tools' `developer-tools-force-celebration-button` shows the celebration without advancing anything.
- Reaching completion by logging through the `session` fixture takes 5 logs across two exercises. Prefer the fixture for the completion stage and use logging only to prove the transition itself.
