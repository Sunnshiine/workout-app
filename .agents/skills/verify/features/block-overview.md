# Block overview

Block Overview shows the whole training Block as a grid of weeks and sessions with each session's state, opens any uploaded session, and lets the athlete make a different session the Current Session or return to it.

## Sub-features

- `block-grid` shows one card per week and one tile per session with `Current`, `Incomplete`, done, or `Not uploaded` state.
- `block-open` opens an uploaded session's stage from its tile.
- `block-inert` leaves a `Not uploaded` tile inert.
- `block-make-current` makes the opened session the Current Session.
- `block-return` returns from a non-current session to the Current Session.

## How to get to it (user POV)

- Tap the session location in the stage header (`Open Block Overview for Week 1, Day 1`).
- The app opens on Block Overview when no session is displayed (`partial-block` fixture).

## Driving it with verify.sh

Preconditions:

- `verify.sh launch partial-block` landed on a `Block 27` heading with `session-tile-W1-D1` valued `Current`.
- For the return path, `verify.sh launch session` and open the grid through the header.

- **Grid.** Capture the grid. Run `verify.sh shot grid`. The tree has `week-card-W2` through `week-card-W4` and tiles `session-tile-W1-D1` (`Current`), `session-tile-W1-D2` (`Incomplete`), `session-tile-W1-D3` (`Not uploaded`).
- **Inert tile.** Tap a `Not uploaded` tile. Run `verify.sh tap --id session-tile-W1-D3`. The `Block 27` heading stays and no `Bench Press` text appears.
- **Open.** Tap an uploaded tile. Run `verify.sh tap --id session-tile-W1-D2`. `find stage-exercise-name` reads `Bench Press` and `find session-location-button` reads `Open Block Overview for Week 1, Day 2`.
- **Make current.** From an opened non-current session, run `verify.sh tap --id make-current-session-button`. `find session-location-button` still names that session and `stage-queue-button` appears.
- **Return.** From the session fixture, run `verify.sh tap --id session-location-button`, then `verify.sh tap --id session-tile-W1-D3`, then `verify.sh tap --id go-back-current-session-button`. `find session-location-button` reads `Open Block Overview for Week 1, Day 1` and `Back Squat` is on the stage.
- **Proof.** Shoot the grid and the opened session and quote the tile value and the location label.

## Gotchas

- Tiles are `AXGenericElement`, not buttons. `tap --id` still resolves them; `--element-type Button` does not.
- Which tiles are uploaded differs per fixture. `session` (full block) has every session uploaded; `partial-block` does not.
- `session-tile-W1-D1` shows `Current` even after opening another session; only `make-current-session-button` changes it.
- The grid pushes onto the stage. A `BackButton` labeled `Back` returns without changing the displayed session.
