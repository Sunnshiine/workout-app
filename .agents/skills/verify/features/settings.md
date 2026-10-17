# Settings

<!-- doc-symbols: not-in-tree BackButton -->

Settings lets the athlete pick appearance, set rest timers, see and change the connected training sheet, sync now, sign out, copy the build identity, and reach Developer Tools.

## Sub-features

- `settings-appearance` switches between `System`, `Light`, and `Night`.
- `settings-rest` steps the standard and superset rest durations.
- `settings-sheet` shows the connected sheet and switches to another one, with a confirmation when writes are pending.
- `settings-sync` triggers a sync and shows its outcome on the row.
- `settings-sign-out` signs out, with a confirmation when writes are pending.
- `settings-build` shows the build identity in the footer and copies it on tap.
- `settings-developer-tools` opens Developer Tools with the Current Session debug info, the *Show Load Basis* switch (`developer-tools-shows-load-basis-toggle`, driven in `log-a-set.md`), the Live Activity Lab, pending writes, and the write log.

## How to get to it (user POV)

- From the stage, tap the session location in the header (`session-location-button`) to open Block Overview, then the gear at its foot (`block-overview-settings-row`, labeled `Settings`). Settings opens as a sheet with a checkmark button labeled `Done`.
- Open the app straight into Settings (`settings` fixture).

## Driving it with verify.sh

Preconditions:

- `verify.sh launch settings -UITEST_PENDING_WRITE` shows a `Settings` heading, `settings-training-sheet-row` labeled `Training Sheet, Fixture Training Log`, and `settings-sync-now-button` labeled `Sync now, Refresh workout state`.

- **Appearance.** Tap Night. Run `verify.sh shot appearance-system`, `verify.sh tap --label Night`, `verify.sh shot appearance-night`. The `Night` radio button's value becomes `1`. On the sheet, the Night cell is dark and the System cell follows the simulator's appearance. Tap `System` to restore.
- **Rest.** Run `verify.sh tap --id settings-standard-rest-stepper-Increment`. `find settings-standard-rest-stepper` reads `Standard, 2:30`. Run `verify.sh tap --id settings-superset-rest-stepper-Increment`. `find settings-superset-rest-stepper` reads `Superset rest, 1:00`.
- **Sync now.** Run `verify.sh tap --id settings-sync-now-button`. The row reads `Sync now, Refresh workout state` and no alert appears. `-UITEST_PENDING_WRITE` logs `225x8@8` on Week 1 Day 1's BB RDL at boot and leaves it queued, so the sync writes it to `'Block 27'!K20`, the visible row under the RDL's Coach Note, and reloads the Block from the Scenario's own workbook. Developer Tools then reads `No pending or conflicted writes` under `Pending Sheet Writes`, and its write log shows that write as `Succeeded`. Launched as `session -UITEST_PENDING_WRITE` and reached through Block Overview, the stage reads `4 Sets left` before the sync and after it, with the RDL's Set 1 logged `225x8@8` both times, because the log is already in the store and the sync only lands it. A Set log under the flag flushes the boot's write too. The sync empties the queue, so relaunch before the switch and sign-out steps. Under `-UITEST_OFFLINE` the fixture sheet is unreachable after the boot and the row reads `Sync now, Offline`.
- **Build footer.** Run `verify.sh tap --id settings-build-identity-footer`, then at once `verify.sh find settings-build-identity-footer`. The label reads `Copied` for about a second in place of the build identity (`1.0 (1) · local build`).
- **Switch sheet with pending writes.** Run `verify.sh tap --id settings-training-sheet-row`. The sheet picker appears with `sheet-picker-done-button`. Run `verify.sh tap --label "Replacement Training Log, 25y ago"`. A confirmation titled `You have unsynced changes. Switch anyway?` offers `Cancel` and `switch-sheet-confirm-button` (labeled `Switch Anyway`) under the body line `Pending logs for the current sheet will be discarded.` Run `verify.sh shot switch-sheet-alert`. A swipe down on the picker, `verify.sh axe swipe --start-x 200 --start-y 150 --end-x 200 --end-y 870 --duration 0.15`, leaves the picker and the card up, as a system alert would. Then run `verify.sh tap --id switch-sheet-confirm-button`. The picker closes and the row reads `Training Sheet, Replacement Training Log`.
- **Sign out with pending writes.** Relaunch `settings -UITEST_PENDING_WRITE`. Run `verify.sh tap --id settings-sign-out-button`. A confirmation titled `You have unsynced changes. Sign out anyway?` appears with `Cancel` and `sign-out-confirm-button` (labeled `Sign Out`) under the same body line. Run `verify.sh shot sign-out-alert`. Run `verify.sh tap --label Cancel` and the confirmation leaves the tree. Repeat the row tap, then `verify.sh tap --id sign-out-confirm-button`. The confirmation is gone, the sheet row reads `Training Sheet, Google Sheet`, and the sync row reads `Sync now, Connect a sheet first`.
- **Developer Tools.** Launch `settings -UITEST_SLOW_SYNC`. Run `verify.sh tap --id settings-developer-tools-row`. A `Developer Tools` heading appears with `current-session-debug-resolved-value` reading `Week 1, Day 1`, `developer-tools-live-activity-lab-link`, and `Pending Sheet Writes`. `verify.sh find developer-tools-sync-button`, `find copy-write-log-button`, and `find clear-write-log-button` each print their button and report it off-screen.
- **Rows disabled during a sync.** `-UITEST_SLOW_SYNC` holds the fixture's tab-list read open for 20 s, so a mid-sync state stays on screen. Still in Developer Tools, run `verify.sh swipe up` twice, tap `developer-tools-sync-button`, then tap `--label Settings` in the navigation bar. Until the sync finishes, `verify.sh find` says `disabled` for `settings-training-sheet-row`, `settings-sync-now-button` and `settings-sign-out-button`, and the sync row reads `Sync now, Syncing...`. This is a sync Settings did not start, the background case.
- **From the stage.** Launch `session`. Run `verify.sh tap --id session-location-button`, then `verify.sh tap --id block-overview-settings-row`. `verify.sh find settings-done-button` prints its line. `verify.sh tap --id settings-done-button` returns to Block Overview, where `verify.sh find block-overview-settings-row` prints the row again. `verify.sh tap --label Back` returns to the stage with `stage-exercise-name` reading `Back Squat`.
- **Proof.** On the sheet, `appearance-system` and `appearance-night` are one screen in light and dark chrome, so the pair proves the switch only while the simulator itself is light. Both still read `Standard 2:00` and `Superset rest 0:30`, because **Rest** runs after them. Both confirmations are the app's own card, not a system alert, because an `.alert` action drops its icon on iOS 26. `switch-sheet-alert` is the picker dimmed behind the card, and `sign-out-alert` is Settings dimmed behind it. Each card carries the two sentences over a text `Cancel` capsule on the left and a capsule holding the red action glyph on the right (`arrow.left.arrow.right` to switch, `rectangle.portrait.and.arrow.right` to sign out). Neither card shows a pending-write count anywhere, so `-UITEST_PENDING_WRITE` is visible only as the alert existing at all.

## Gotchas

- In the `settings` fixture Settings is the root screen, so `Done` and a confirmed sign out both leave it on screen. The signed-out wall is in `onboarding.md`.
- Without `-UITEST_PENDING_WRITE` sign out and a sheet switch skip their confirmations.
- Settings opened from Block Overview is a sheet, and the tree keeps the grid's `block-overview-settings-row`, labeled `Settings`, under it. In Developer Tools the back button is also labeled `Settings`, so `tap --label Settings` lists both and taps neither. Return with `verify.sh tap --id BackButton`.
- The sheet row's label ends in the sheet's age, counted from today, so `Replacement Training Log, 25y ago` expires. Read the live label from `verify.sh tree` and match all of it (`onboarding.md`).
- `developer-tools-live-activity-lab-link` opens, but a launch from this file passes `-UITEST_DISABLE_LIVE_ACTIVITIES`, so the Lab's status row reads `Live Activities disabled` over `Prototype is stopped.` and `find` says `disabled` for four of the five buttons under `Controls`. The fifth, `live-activity-lab-restart-rest-button`, stays enabled, and tapping it leaves both status lines unchanged, so an enabled control there is not a working Lab. The variant picker and the Sample Workout State steppers stay enabled too. That is the harness, not a defect. The Lab itself is driven in `live-activity.md`, which launches under `VERIFY_LIVE_ACTIVITIES=1`.
