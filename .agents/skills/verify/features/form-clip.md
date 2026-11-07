# Form Clip

A Form Clip is a movie attached to one Logged Set, kept on the phone and never written to the Sheet. The athlete adds one from the Set's card, reviews it full screen in slow motion, traces the Bar Path with a tap on the plate, compares it to the previous clip of the same Movement, and shares it with the Set's facts as the caption.

## Sub-features

- `clip-add` adds a movie from Photos to a Logged Set, from the card's glyph or the held Set's More menu, then opens the review on it.
- `clip-review` plays the clip in the Night room: scrub, 0.25× and 0.5×, frame step, loop. A movie pulled down closes the room.
- `clip-bar-path` follows the plate from one tap on a paused frame and draws the path over the movie, and says where a lost plate stopped it.
- `clip-compare` shows two clips of a Movement side by side, opening on the previous one across Sessions, played from a marked start.
- `clip-share` shares the movie under a readable name with the caption.
- `clip-many` holds more than one clip on a Set, with a position pill that steps through them.
- `clip-storage` lists every clip and its size in Settings, and deletes one.
- `clip-record` films a clip with the camera. The Simulator has no camera, so it stays unverified here.

## How to get to it (user POV)

- A Logged Set's card, reviewed from its leaf: the glyph left of the mic, `Add Clip` while it holds none, and `Review clip` once it holds one.
- The More menu on a Set held after a spoken write holds `Add Clip` and `Clear`. The system chooses their order, and `Clear` showed on top on iPhone 17 Pro, so press by label.
- Inside a review: the `More` menu's `Add Clip`, `Retrace Bar Path`, and `Delete Clip`, and the `Compare` glyph at the foot.
- Settings from the Block grid's gear: the `Form Clips` row, then a row to review it or its trash to delete it.

## Driving it with verify.sh

Preconditions:

- Seed a labelled synthetic movie, then add it to the Simulator's Photos: `uv run python3 scripts/form-clip-seed.py /tmp/squat.mp4`, then `xcrun simctl addmedia "$SIM" /tmp/squat.mp4`. Run `verify.sh launch session -UITEST_OFFLINE`, log Set 1 with `verify.sh tap --id log-active-set-button`, and reopen it from the branch leaf `Set 1, 237.5x5@6`.

- **Add.** Press `form-clip-button`, then `Add Clip`. The picker opens over the app. Press the movie's tile. The review opens by itself, `form-clip-title` reads `Back Squat`, `form-clip-facts` reads `W1 D1 · Set 1 · 237.5×5 @6`, and the card behind it reads `Review clip`. Run this once under `verify.sh launch --animated`, and read the time under the scrubber moving in the review the add opened. A short movie's import lands while the picker's cover is still leaving, which shows the review, takes it away, and shows it again on one player, and only motion on does that.
- **Review.** Press `form-clip-play` to pause, `form-clip-step-forward` six times, and `form-clip-rate-0.25×`. The time under the scrubber moves 0.2 s on the steps, and about 1 s for each 4 s of play at 0.25×.
- **Bar Path.** Drag the scrubber to 0:00.0 with `verify.sh axe swipe --start-x 336 --start-y 665 --end-x 10 --end-y 665 --delta 8`, press `form-clip-bar-path`, and `form-clip-status` reads `Find where the Set starts, then tap the center of the plate.` over a green stroke on the frame. Press the plate at its point in the frame. The status line and the stroke clear and a green path shows with a dot on the plate.
- **Pull to close.** Drag the movie downward at least 96 points, with `verify.sh axe swipe --start-x 200 --start-y 300 --end-x 200 --end-y 500 --delta 8`. The review closes. A shorter drag falls back, and so does one on a Compare pane that starts sideways, which scrubs that pane.
- **Lost plate.** Seed with `--lost-at 4.3` and trace as above. `form-clip-status` reads `The path stops at 0:04.3, where the plate was lost.`
- **Damaged movie.** Overwrite the back half of a traced clip's movie in the app's container with zeros, then press `form-clip-more`, `Retrace Bar Path`, and the plate. `form-clip-status` reads `This movie can't be read frame by frame, so it can't be traced.` The saved path stays on the movie, and the clip's JSON record keeps its old `barPath` and its save time.
- **Compare.** Press `form-clip-compare`. With no other clip of the Movement the room reads `No other clip of Back Squat`, and `form-clip-compare-add` opens the picker. With one on another Set, `form-clip-pane-left` and `form-clip-pane-right` show both, and `form-clip-mark-left` stores the frame on screen as that clip's start. Drag both panes and press both flags, in either order. Neither pane moves, and each clip's `startMark` in its JSON record is the frame its own pane showed.
- **Share.** Press `form-clip-share`. The share sheet names the file `Back Squat W1 D1 Set 1`. Press `Copy`, and `xcrun simctl pbpaste "$SIM"` prints `Back Squat · W1 D1 · Set 1 · 237.5×5 @6`.
- **Many.** Press `form-clip-more`, then `Add Clip`, and pick again. `form-clip-next` reads `1 of 2`, and pressing it reads `2 of 2`. The card reads `Review 2 clips`.
- **Delete.** Press `form-clip-more`, `Delete Clip`, then the card's `form-clip-delete-confirm`. The review moves to the clip that is left, and `form-clip-next` is gone.
- **Storage.** Run `verify.sh launch settings`, since clips survive a launch. `settings-form-clips-row` reads the count and the total. Press it, and each `form-clip-row` reads its name, its size, and its line. Press a `form-clip-row-delete`, and the bar's Back button leaves the tree until the card is answered. Delete the last one, and `form-clips-empty` reads `No clips on this phone. Add one from a Logged Set's card.`
- **Proof.** Clips sit in the app's container, under `Library/Application Support/Form Clips`, one movie and one JSON record each, and the record holds the `barPath` and the `startMark`. The arc across processes runs in the CLI with no Simulator: `workout init --scenario fresh-block`, `workout log w1d1.e0.s0 185x5@8`, `workout clip add w1d1.e0.s0 /tmp/squat.mp4`, `workout clip trace <id> --x 0.46 --y 0.3`, `workout flush`, `workout sheet --cell K15`, which reads `185x5@8`, the Set Log alone.

## Gotchas

- `axe tap`'s default style can report success without landing on a loaded host. Pass `--tap-style physical`, or use `verify.sh axe touch -x X -y Y --down --up --delay 0.15`. A `Menu` needs the delay, and a second tap closes what the first opened.
- Touches can stop landing while `doctor` reads all ok and `tap` reports success, seen after `simctl ui content_size` on a loaded host and after a `scripts/test-sim.sh` run. Shut your own simulator down, boot it with `simctl boot` and `simctl bootstatus`, then `verify.sh install` and `launch`.
- `verify.sh record` fails with OSStatus -12204 when the evidence directory is where `simctl recordVideo` can't write. Set `VERIFY_EVIDENCE` to a directory under `/tmp` for the take, then copy the take back.
- The picker's contents are outside the tree, so press its tile by point: the first tile sits near `66,352` on iPhone 17 Pro.
- `axe swipe`'s default delta is coarse enough that a short drag moves nothing. Pass `--delta 2` or more.
- The tree lists the stage under a full-screen cover along with the cover's own elements, so a label found there does not prove it is on top. Read the shot.
- `form-clip-scrubber` prints a value of `nan` in the tree. VoiceOver reads its text, `0:07.0 of 0:09.0`.
- Clips survive a fixture launch, because they live beside the app's data and not in its store. A previous run's clips still show on the next one.
- A movie that autoplays moves on while a slow host takes its shots, so pause before reading the time.
