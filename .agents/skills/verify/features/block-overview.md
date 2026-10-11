# Block overview

Block Overview shows the whole training Block as a grid of weeks and sessions with each session's state, opens any uploaded session, and lets the athlete make a different session the Current Session or return to it.

## Sub-features

- `block-grid` shows the Current Session's week as full tiles and every other week as a card of mini tiles, each tile valued `Current`, `Incomplete`, `Complete`, or `Not uploaded`.
- `block-open` opens an uploaded session's stage from its tile, full or mini.
- `block-inert` leaves a `Not uploaded` tile inert.
- `block-make-current` makes the opened session the Current Session.
- `block-return` returns from a non-current session to the Current Session.

## How to get to it (user POV)

- Tap the session location in the stage header (`Open Block Overview for Week 1, Day 1`).
- The app opens on Block Overview when no session is displayed (`partial-block` fixture).
- Move On from the last uploaded session lands on the grid (`session-completion.md`).

## Driving it with verify.sh

Preconditions:

- `verify.sh launch partial-block` landed on a `Block 27` heading with `session-tile-W1-D1` valued `Current`.

- **Grid.** Capture the grid. Run `verify.sh shot grid`. The tree has tiles `session-tile-W1-D1` (`Current`), `session-tile-W1-D2` (`Incomplete`), `session-tile-W1-D3` (`Not uploaded`), and cards `week-card-W2` through `week-card-W4`, each holding mini tiles such as `session-tile-W2-D1` (`Incomplete`). Week 1 has no card because the Current Session's week is the expanded one.
- **Inert tile.** Tap a `Not uploaded` tile. Run `verify.sh tap --id session-tile-W1-D3`, then `verify.sh shot inert`. It prints `no tree changes` and `verify.sh find stage-exercise-name` exits 1.
- **Open.** Tap an uploaded tile. Run `verify.sh tap --id session-tile-W1-D2`. `find stage-exercise-name` reads `Bench Press`, `find session-location-button` reads `Open Block Overview for Week 1, Day 2`, and `make-current-session-button` and `go-back-current-session-button` appear. Run `verify.sh shot opened-session`.
- **Make current.** Run `verify.sh tap --id make-current-session-button`. `verify.sh find make-current-session-button` and `verify.sh find go-back-current-session-button` both exit 1. Run `verify.sh tap --id session-location-button`. `session-tile-W1-D2` is valued `Current` and `session-tile-W1-D1` `Incomplete`. Run `verify.sh shot grid-after-make-current`, then `verify.sh diff grid grid-after-make-current`, whose only four changed lines are those two tiles trading `Current` for `Incomplete`.
- **Open from a collapsed week.** On the grid, run `verify.sh tap --id session-tile-W2-D1`. `find session-location-button` reads `Open Block Overview for Week 2, Day 1` and `find stage-exercise-name` reads `Deadlift`.
- **Return.** Launch `session`. Run `verify.sh tap --id session-location-button`, then `verify.sh tap --id session-tile-W1-D3`, then `verify.sh tap --id go-back-current-session-button`. `find session-location-button` reads `Open Block Overview for Week 1, Day 1`, `Back Squat` is on the stage, and `verify.sh find go-back-current-session-button` exits 1.
- **Proof.** On the sheet, `grid` and `inert` are the same image, which is what the inert tap looks like. Week 1 reads as a solid green ring on Day 1, a plain pale outline on Day 2, and dashed outlines on Days 3 and 4, so `Not uploaded` is drawn as a dashed border and nothing else, repeated in miniature on the Week 2 to Week 4 cards under `0 of 4 · 3 not uploaded`. `opened-session` shows the two session controls as bare glyphs, a back arrow at the top left for `go-back-current-session-button` and a pin at the top right for `make-current-session-button`, so those names exist only in the tree. `grid-after-make-current` is `grid` with the green ring moved one tile right and nothing else changed.

## Gotchas

- Tiles are `AXGenericElement`, not buttons. `tap --id` still resolves them; `--element-type Button` does not.
- Which tiles are uploaded differs per fixture. `session` (full block) has every session uploaded; `partial-block` does not.
- `session-tile-W1-D1` shows `Current` even after opening another session; only `make-current-session-button` changes it.
- `stage-queue-button` is on every opened session's stage, so it says nothing about which session is current.
- The grid pushes onto the stage. A `BackButton` labeled `Back` returns without changing the Viewed Session.
