# Settings

Settings lets the athlete pick appearance, set rest timers, see and change the connected training sheet, sync now, sign out, copy the build identity, and reach Developer Tools.

## Sub-features

- `settings-appearance` switches between `System`, `Light`, and `Night`.
- `settings-rest` steps the standard and superset rest durations.
- `settings-sheet` shows the connected sheet and switches to another one, with a confirmation when writes are pending.
- `settings-sync` triggers a sync and shows its outcome on the row.
- `settings-sign-out` signs out, with a confirmation when writes are pending.
- `settings-build` shows the build identity in the footer and copies it on tap.
- `settings-developer-tools` opens Developer Tools with the Current Session debug info, the Live Activity Lab, pending writes, and the write log.

## How to get to it (user POV)

- Over-pull the session header downward. The header HUD opens into the session controls, whose gear (`session-controls-settings-button`) presents Settings with a `Done` button.
- Open the app straight into Settings (`settings` fixture).

## Driving it with verify.sh

Preconditions:

- `verify.sh launch settings -UITEST_PENDING_WRITE` shows a `Settings` heading, `settings-training-sheet-row` labeled `Training Sheet, Fixture Training Log`, and `settings-sync-now-button` labeled `Sync now, Refresh workout state`.

- **Appearance.** Tap Night. Run `verify.sh shot appearance-system`, `verify.sh tap --label Night`, `verify.sh shot appearance-night`. The `Night` radio button's value becomes `1`. On the sheet, the Night cell is dark and the System cell follows the simulator's appearance. Tap `System` to restore.
- **Rest.** Run `verify.sh tap --id settings-standard-rest-stepper-Increment`. `find settings-standard-rest-stepper` reads `Standard, 2:30`. Run `verify.sh tap --id settings-superset-rest-stepper-Increment`. `find settings-superset-rest-stepper` reads `Superset rest, 1:00`.
- **Sync now.** Run `verify.sh tap --id settings-sync-now-button`. The row reads `Sync now, Offline` and no alert appears. The fixture's sheet is unreachable by design, so `Offline` proves the tap and the outcome row, not the network.
- **Build footer.** Run `verify.sh tap --id settings-build-identity-footer`, then at once `verify.sh find settings-build-identity-footer`. The label reads `Copied` for about a second in place of the build identity (`1.0 (1) · local build`).
- **Switch sheet with pending writes.** Run `verify.sh tap --id settings-training-sheet-row`. The sheet picker appears with `sheet-picker-done-button`. Run `verify.sh tap --label "Replacement Training Log, 25y ago"`. An alert titled `You have unsynced changes. Switch anyway?` offers `Switch Anyway` and `Cancel` over the body line `Pending logs for the current sheet will be discarded.` Run `verify.sh shot switch-sheet-alert`, then `verify.sh tap --label "Switch Anyway"`. The picker closes and the row reads `Training Sheet, Replacement Training Log`.
- **Sign out with pending writes.** Relaunch `settings -UITEST_PENDING_WRITE`. Run `verify.sh tap --id settings-sign-out-button`. An alert titled `You have unsynced changes. Sign out anyway?` appears with `Cancel` and `Sign Out` under the same body line. Run `verify.sh shot sign-out-alert`. Run `verify.sh tap --label Cancel` and the alert leaves the tree. Repeat the row tap, read the alert's `Sign Out` button frame from `verify.sh tree` (`@205,484 140x48` on this device), and tap its center with `verify.sh tap -x 275 -y 508`. The alert is gone, the sheet row reads `Training Sheet, Google Sheet`, and the sync row reads `Sync now, Connect a sheet first`.
- **Developer Tools.** Launch `settings -UITEST_SLOW_SYNC`. Run `verify.sh tap --id settings-developer-tools-row`. A `Developer Tools` heading appears with `current-session-debug-resolved-value` reading `Week 1, Day 1`, `developer-tools-live-activity-lab-link`, and `Pending Sheet Writes`. `verify.sh find developer-tools-sync-button`, `find copy-write-log-button`, and `find clear-write-log-button` each print their button and report it off-screen.
- **Rows disabled during a sync.** `-UITEST_SLOW_SYNC` holds the fixture's tab-list read open for 20 s, so a mid-sync state stays on screen. Still in Developer Tools, run `verify.sh swipe up` twice, tap `developer-tools-sync-button`, then tap `--label Settings` in the navigation bar. Until the sync finishes, `verify.sh find` says `disabled` for `settings-training-sheet-row`, `settings-sync-now-button` and `settings-sign-out-button`, and the sync row reads `Sync now, Syncing...`. This is a sync Settings did not start, the background case.
- **From the stage.** Launch `session`, drag the header down, tap the gear. Run `verify.sh axe swipe --start-x 200 --start-y 90 --end-x 200 --end-y 420 --duration 0.4` then at once `verify.sh tap --id session-controls-settings-button --wait-timeout 0`. A `Settings` heading and `settings-done-button` appear. `verify.sh tap --id settings-done-button` returns to the stage with `stage-exercise-name` reading `Back Squat`.
- **Proof.** On the sheet, `appearance-system` and `appearance-night` are one screen in light and dark chrome, so the pair proves the switch only while the simulator itself is light. Both still read `Standard 2:00` and `Superset rest 0:30`, because **Rest** runs after them. `switch-sheet-alert` is the picker dimmed behind a stacked alert, `Switch Anyway` as red text above a plain `Cancel`, and the alert covers the `Replacement Training Log` row it was tapped from down to one character at the left edge. `sign-out-alert` carries the same two sentences over Settings, but its buttons sit side by side with `Sign Out` a filled red capsule on the right, which is why that one needs a frame read and a coordinate tap. Neither alert cell shows a pending-write count anywhere, so `-UITEST_PENDING_WRITE` is visible only as the alert existing at all.

## Gotchas

- In the `settings` fixture Settings is the root screen, so `Done` and a confirmed sign out both leave it on screen. The signed-out wall is in `onboarding.md`.
- Without `-UITEST_PENDING_WRITE` sign out and a sheet switch skip their confirmations.
- The session controls hide again after a moment of idleness. Tap the gear in the same breath as the drag, with `--wait-timeout 0`, or the reveal is gone.
- The sheet row's label ends in the sheet's age, counted from today, so `Replacement Training Log, 25y ago` expires. Read the live label from `verify.sh tree` and match all of it (`onboarding.md`).
- `developer-tools-live-activity-lab-link` opens, but a launch from this file passes `-UITEST_DISABLE_LIVE_ACTIVITIES`, so the Lab's status row reads `Live Activities disabled` over `Prototype is stopped.` and `find` says `disabled` for four of the five buttons under `Controls`. The fifth, `live-activity-lab-restart-rest-button`, stays enabled, and tapping it leaves both status lines unchanged, so an enabled control there is not a working Lab. The variant picker and the Sample Workout State steppers stay enabled too. That is the harness, not a defect. The Lab itself is driven in `live-activity.md`, which launches under `VERIFY_LIVE_ACTIVITIES=1`.
