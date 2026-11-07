# Lock Screen Logging

<!-- doc-symbols: not-in-tree ListCell ReduceMotionEnabled -->

During a rest the Lock Screen card shows the Set the stage's card is on, with that Exercise's Last Performed. One tap on an RPE Chip logs the Set at the card's own pre-fill and that RPE, without unlocking. The press runs in the app's process, through the same store call as the Log capsule, so the rest restarts, the card moves on, and the write queues. A Set whose pre-fill is not complete (an AMRAP, a Timed Set, no load) shows no chips and leaves the mic and the app.

## Sub-features

- `lock-screen-offer` draws Last Performed from a past Session, the values a chip logs, what the prescription says beyond them and the unsynced count beside them, and the RPE Chips, with a tick under the prescribed RPE.
- `lock-screen-press` logs at the tapped RPE, reads back `Logged 252.5×5 @7`, restarts the rest, then shows the next Set.
- `lock-screen-refusal` writes nothing for a press the Set no longer matches. A Set that settled leads with `That tap changed nothing` in the plain text colour over what it holds, as `Set 3 of 3 holds 267.5×5 @8.5`, under the Exercise of the pressed Set. Any other reason reads `Not logged` over why.
- `lock-screen-needs-app` leads with the prescription and shows an `Unlock to log` control in place of the chips, beside the mic.
- `lock-screen-open-app` opens the app from the row's last control, for an RPE no chip shows.
- `lock-screen-island` offers the same chips on the expanded Dynamic Island.

## How to get to it (user POV)

- Log a Set on the session stage and lock the phone. The card is on the Lock Screen for as long as the rest's activity runs.
- Tap an RPE Chip. The card reads back the Set Log, then shows the next Set.
- Long press the Dynamic Island with the app behind for the same chips.

## Driving it with verify.sh

Preconditions:

- Every launch here takes `VERIFY_LIVE_ACTIVITIES=1`. `-UITEST_OFFLINE` keeps each write queued, so `Sync status` counts them.
- Run this on a simulator of your own, because locking it wedged a shared one's screenshots (`live-activity.md`, Gotchas). `verify.sh axe touch` lands where `tap` reports success and does nothing on a loaded host.
- A touch longer than about 0.2 s on `log-active-set-button` can start its hold, so give it `--delay 0.12`.

The drive:

- **Offer.** Run `VERIFY_LIVE_ACTIVITIES=1 verify.sh launch session -UITEST_OFFLINE`, touch `log-active-set-button`, read off the tree since large type moves it, then `verify.sh axe button lock --duration 0.3`. Touch the screen, and on the first activity of an install touch `Allow`, read off `tree --all`. `verify.sh shot offer` shows `Back Squat`, `Block 26 · W4 D3 — 245×5 @6, 255×5 @7`, `252.5 × 5`, `1 unsynced · 2 Sets left`, chips `6 6.5 7 7.5 8` with the tick under 7, and the last control's ellipsis. `tree --all` holds only the card, as `ListCell @20,593 363x143`. The chips' row sits 34pt above the card's bottom at any type size, so y=702 here, at x=57, 114, 172, 229, 286, then the ellipsis at 343.
- **Press.** Touch chip 7 at (172,702). The card reads `Logged 252.5×5 @7`, `Set 2 of 3`, and `1 Set left` for 3.5 s, then `267.5 × 5`, `2 unsynced · 1 Set left`, chips `7 7.5 8 8.5 9`. The card stays `363x143` across all three.
- **Prove the write.** Touch the ellipsis at (343,702), which opens the app. The tree reads `Sync status: 2 unsynced`, `Set 2, 252.5x5@7`, `Set 3 of 3`, `Log 267.5 × 5 @8`, and a `rest-pill` under 2 minutes. For the cell, run the CLI on `full-block`, as `Sources/WorkoutCLI/README.md` shows: `workout lock-screen` prints the offer, `workout rpe-chip <setIdentity> 7` logs it, and `workout flush && workout sheet --cell K18` reads `237.5x5@7`.
- **Refuse a stale press.** With the app in front, run `verify.sh axe swipe --start-x 80 --start-y 2 --end-x 80 --end-y 600 --duration 0.4`, which pulls Notification Center over it and moves the card to `@14,598 374x148`, with the chips at y=711 and x=53, 112, 171, 231, 290. Send two touches at once to different chips, each `axe touch ... &`, then `wait`. The values and chips dim where the press lands. Whichever reaches the app second reads `That tap changed nothing` in the plain text colour over `Set 2 of 3 holds 252.5×5 @7`, naming the RPE the first touch logged, for 3.5 s. The next Set's `2 unsynced` counts what one press would have queued. On a loaded host the touches can land seconds after they are sent, so start a `simctl io recordVideo` before them instead of framing after them.
- **No chips.** Press a chip on the last Back Squat Set too. The card moves to `BB RDL`, whose `Drop 17.5%` gives no pre-fill, and reads `8 reps / Drop 17.5%` and `4 unsynced · 2 Sets left` over `Unlock to log`. Touching that opens the app on `BB RDL`, `Set 1 of 2`, `Complete Set Log`. `verify.sh launch worst-case` reaches an AMRAP the same way, with a `Reps` pill and an `RPE` pill touched before the log, and its card reads `AMRAP / Start conservative and work up to a heav…`. Those rails clip, and the tree also lists their hidden pills, so touch a pill whose centre is inside the rail's own frame. The card holds `@20,595 363x142`, a point short of the chips' card, so moving from one to the other does not visibly jump.
- **Large type.** Bring the card up at the default size, then run `xcrun simctl ui "$SIM" content_size extra-extra-extra-large` with the phone locked, touch to wake, and wait about eight seconds. The card is `@20,579 363x157`, the same at `extra-extra-large` and at `accessibility-extra-extra-extra-large`, because it stops growing at the first to keep every line inside the system's 160pt. Read the Last Performed and values lines off a frame, since the tree holds neither.
- **Island.** With the card up, go home and run `axe touch -x 201 -y 32 --down --up --delay 1.0`. Capture it with `verify.sh shot`, because `simctl io screenshot` draws the home screen without it. The tree holds it as `@14,14 374x160`, the countdown centred at the size of the chips, then `Back Squat`, `252.5 × 5`, and `1 unsynced` over the chips. Its type stops growing at the default size, and at `extra-extra-extra-large` the system draws it `@14,14 374x166` with the same content, unclipped. Its line drops the count before it cuts the Exercise's name. A long press under load can read as a tap and open the app, so press for 1.4 s and go home again if the tree shows the stage.
- **Take.** `verify.sh launch --animated session -UITEST_OFFLINE`, drive to the locked card, then `verify.sh record lock-screen-press --tail 22 -- axe touch -x 172 -y 702 --down --up --delay 0.12`, with a background job that touches the ellipsis 16 s in, using the raw `axe` binary. For motion, take the press over the app from Notification Center, where the values dim the moment the press lands and the card crossfades.
- **Reduce Motion.** Run `xcrun simctl spawn "$SIM" defaults write com.apple.Accessibility ReduceMotionEnabled -bool true`, launch, and press. The values dim and the card crossfades, with nothing moving. Set it back to `false` after.
- **Proof.** Quote the `Sync status`, `Set 2,` and `rest-pill` lines from the take's `.end.txt` and the CLI's cell.

## Gotchas

- A dimmed Lock Screen draws the countdown as `1:--`, and after an update it can draw a fixed stale value such as `0:37` until the screen wakes. It reads correctly about seven seconds after a touch, and it matches the stage's `rest-pill`. Trust the pill.
- A dimmed Lock Screen draws no animation, so the recorder holds the card, the readback, and the next Set as cuts. Pull Notification Center over the app to see the crossfade and a ticking countdown.
- `simctl io` cannot write under `~/Projects`, which fails with `Operation not permitted` for a screenshot and `OSStatus error -12204` for a take. Set `VERIFY_EVIDENCE` to a directory under `/tmp` for the drive, then move what you keep.
- Until `Allow` is answered the card is `@20,491 363x246`, and `Don't Allow` sits where chip 7 will be, so a blind touch at y=702 refuses Live Activities for that install. Read `Allow` off the tree first. The prompt can arrive a few seconds after the first wake.
- Over Notification Center the tree also holds a `ListCell @14,0 374x219` that is not the card. Take the cell whose `y` is near the bottom, since the card's own can take seconds to list.
- The card's Last Performed leaves out the Session in progress, so it reads `Block 26 · W4 D3` while the stage's `last-performed-line` reads today's Sets once one is logged.
- `RPEChipPress` reads `cardDraft` from what the card's mic reported, so an edited weight refuses only while the Lock Screen still shows the old value. Leaving the app retargets the card first, so an edit followed by a lock logs the edited weight, which is the card's own.
- The app launched in the background by a press after `simctl terminate` loses its `-UITEST_*` flags and reads `No Session`, so a press against a killed fixture run proves nothing.
