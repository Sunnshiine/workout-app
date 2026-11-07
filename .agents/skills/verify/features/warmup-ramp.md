# Warm-up Ramp

<!-- doc-symbols: not-in-tree BackButton -->

The queue Lens summons a sheet that walks the athlete up to the first Pending Set of the Exercise on stage. A drawn bar shows what goes on each side, the same plates read large under it, and the steps sit beneath. A tap marks a step for this Session alone. Nothing here is logged, counted, or written to the Sheet, and the Set's weight never changes.

## Sub-features

- `warmup-entry` offers the sheet from the Lens header while the Exercise on stage has a ramp to walk, and offers nothing for a bodyweight Set, a Timed Set, a Set the Bar alone outweighs, or while pairing.
- `warmup-walk` lists the steps and the Set they end on. A tap on a row ahead walks to it, and a tap on a Finished step goes back to it.
- `warmup-bar` draws the current step's plates to scale, one side mirrored, with the sleeve in view at any load.
- `warmup-pick` lets the athlete pick a top with the rail when the Set gave no weight.
- `warmup-honest` loads the nearest weight below when the Plate Inventory cannot make the Set's, and the Set's row says so.
- `warmup-inventory` follows the Bar and the plates on the Settings page, covered in [Settings](./settings.md). The walk survives a changed Bar.

## How to get to it (user POV)

- From the stage, tap the queue button, then the barbell button in the Lens header.
- `workout warmup <set-address>` prints the same ramp, covered in [Headless CLI](./cli-headless.md).

## Driving it with verify.sh

Preconditions:

- `verify.sh launch session` landed on Back Squat, and `verify.sh find stage-queue-button` reads `Queue` valued `1 of 2`.

- **Open.** Run `verify.sh tap --id stage-queue-button`, then `verify.sh tap --id stage-queue-warmup`. The tree has `warmup-bar` labeled `Bar, 45 lb, nothing on it`, `warmup-step-45` valued `Current`, then `warmup-step-80`, `warmup-step-120`, `warmup-step-160`, `warmup-step-195`, and `warmup-set` labeled `Set 1 is 237.5 pounds, loads as 235`, which reads `237.5` then `Set 1, loads as 235`.
- **Walk.** Run `verify.sh tap --id warmup-step-45`, then `verify.sh shot walked`. It prints `warmup-step-45` valued `Finished`, `warmup-step-80` valued `Current`, and `warmup-bar` labeled `10 and 5 and 2.5 a side`.
- **Walk back.** Run `verify.sh tap --id warmup-step-45`. `warmup-step-45` is `Current` again.
- **Reach the Set.** Run `verify.sh tap --id warmup-set`. Every step reads `Finished`, `warmup-set` reads `Current`, and `warmup-bar` is labeled `2 times 45 and 5 a side`.
- **Keep it for the Session.** Swipe the sheet down and tap `stage-queue-warmup` again. The walk is where it was. `verify.sh find log-active-set-button` and the Set's weight are unchanged.
- **Pick a top.** Relaunch, run `verify.sh tap --id stage-up-next`, open the sheet, and read `warmup-note` labeled `Pick Set 1’s weight.` with no `warmup-bar`. Run `verify.sh tap --id warmup-top-135`. `warmup-bar` appears, and the steps read 45, 60, 80, 95, 115, and `warmup-set` labeled `Set 1, 135 pounds`.
- **Worst cases.** Launch with `-UITEST_COACH_EDIT`, then sync through `session-location-button`, `block-overview-settings-row`, `settings-sync-now-button`, `settings-done-button`, and `BackButton`. `E7=1340` tops out at `10 × 45 + 25 + 5`. `E7=180` walks 45, 60, 80, 95, 115, 135. `E7=63.33` shows one row, `warmup-set` labeled `Set 1 is 47.5 pounds, loads as 45`. With `H15=BW`, `F15=40 sec`, or `E7=40` (a 30 lb Set under the 45 lb Bar), `verify.sh find stage-queue-warmup` exits 1 in the Lens. `E7=53.33` is a 40 lb Set: the entry is gone on the 45 lb Bar, and `settings-bar-35` brings it back.
- **A changed gym.** On `settings-plates-row`, tap `settings-bar-35`. Back in the sheet the walk reads 35, 75, 115, 155, 195, and on its first step `warmup-bar` is labeled `Bar, 35 lb, nothing on it`. Turn off `settings-plate-2.5` on the 45 lb Bar and the walk reads 45, 75, 115, 155, 195.
- **Motion.** Run `verify.sh launch --animated session`, open the sheet, then `verify.sh record walk -- tap --id warmup-step-45`. Read frames across the move: plates slide on from the sleeve's open end, off the same way, both sides stay level on the shaft, one capsule travels between the rows, and the readout cuts to the new load. Under Reduce Motion the plates and the capsule are at their end on the first changed frame too, and only the rows' ink and checkmark fade.
- **Proof.** On the sheet, `walked` shows plates on both sleeves with the same readout beneath, one row in a capsule, and a checkmark above it. A CLI drive proves the ramp's numbers with no simulator: see [Headless CLI](./cli-headless.md).

## Gotchas

- The rows sit on a large sheet, and the tree still lists the Active Set Card beneath it, so a card id resolving does not mean the sheet closed.
- A press at a plate row's centre does not flip its switch, because a native Toggle answers on the switch. Touch the switch itself: `verify.sh axe touch -x 350 -y <row centre> --down --up --delay 0.2`.
- 47.5 on a 45 lb Bar needs 1.25 a side, so it cannot be built with or without 2.5s. To see a plate's removal change the ramp, use the session fixture's Back Squat.
- Under heavy host load a zero-length tap can report success and do nothing. Use `verify.sh hold <id> 0.2`, and re-read the tree after each one.
- `simctl recordVideo` may refuse a path under the main checkout with `Code=513`. `VERIFY_EVIDENCE=/tmp/<dir>` films to a path it can write, and the take copies across afterwards.
- `axe batch --file` runs several touches as one `record` drive, which is how a whole walk gets filmed.
