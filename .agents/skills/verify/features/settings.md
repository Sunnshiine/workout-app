# Settings

Settings lets the athlete pick appearance, set rest timers, see and change the connected training sheet, sync now, sign out, and reach Developer Tools.

## Sub-features

- `settings-appearance` switches between `System`, `Light`, and `Night`.
- `settings-rest` steps the standard and superset rest durations.
- `settings-sheet` shows the connected sheet and opens the sheet picker.
- `settings-sync` triggers a sync.
- `settings-sign-out` signs out, with a confirmation when writes are pending.
- `settings-developer-tools` opens Developer Tools with the Current Session debug info, pending writes, and actions.

## How to get to it (user POV)

- Over-pull the session header downward. The header HUD opens into the session controls, whose gear (`session-controls-settings-button`) presents Settings with a `Done` button.
- Open the app straight into Settings (`settings` fixture).

## Driving it with verify.sh

Preconditions:

- `verify.sh launch settings -UITEST_PENDING_WRITE` for the sign-out confirmation, or `verify.sh launch settings` otherwise.
- The tree has a `Settings` heading and `settings-training-sheet-row` labeled `Training Sheet, Fixture Training Log`.

- **From the stage.** Launch `session`, drag the header down, tap the gear. Run `verify.sh axe swipe --start-x 200 --start-y 90 --end-x 200 --end-y 420 --duration 0.4` then at once `verify.sh tap --id session-controls-settings-button --wait-timeout 0`. A `Settings` heading and `settings-done-button` appear. `verify.sh tap --id settings-done-button` returns to the stage with `stage-exercise-name` reading `Back Squat`.
- **Appearance.** Tap Night. Run `verify.sh tap --label Night`. The `Night` radio button's value becomes `1` and the screenshot is dark. Tap `System` to restore.
- **Rest.** Increment standard rest. Run `verify.sh tap --id settings-standard-rest-stepper-Increment`. `find settings-standard-rest-stepper` reads a longer duration than `Standard, 2:00`.
- **Sheet row.** Run `verify.sh tap --id settings-training-sheet-row`. The sheet picker appears with `sheet-picker-done-button`. Tap it to return.
- **Sync now.** Run `verify.sh tap --id settings-sync-now-button`. The button stays and no error alert appears (the fixture sheets client answers instantly).
- **Rows disabled during a sync.** Launch `settings -UITEST_SLOW_SYNC`, which holds every fixture Sheet read open for 20 s so a mid-sync state stays on screen. Tap `settings-developer-tools-row`, run `verify.sh swipe up` twice, tap `developer-tools-sync-button`, then tap `--label Settings`. `settings-training-sheet-row`, `settings-sync-now-button` and `settings-sign-out-button` all report `enabled=false` in `axe describe-ui`, and `Sync now` reads `Syncing...`, until the sync finishes. Developer Tools starts that sync outside Settings' own `SettingsSyncActivity`, so this is the background case, not the `Sync now` one.
- **Sign out with pending writes.** Run `verify.sh tap --id settings-sign-out-button`. An alert titled `You have unsynced changes. Sign out anyway?` appears with `Cancel` and `Sign Out`. Run `verify.sh tap --label Cancel` and the alert leaves the tree. Repeat the row tap, read the alert's `Sign Out` button frame from `verify.sh tree` (`@205,484 140x48` on this device), and tap its center with `verify.sh tap -x 275 -y 508`. The alert is gone and the onboarding `Connect Google Sheet` button appears.
- **Developer Tools.** Run `verify.sh tap --id settings-developer-tools-row`. A `Developer Tools` heading appears with `Current Session Debug Info`, `current-session-debug-resolved-value` reading `Week 1, Day 1`, and `Pending Sheet Writes`. `verify.sh find developer-tools-sync-button` prints the Sync button and reports it off-screen. Tap `--label Settings` in the navigation bar to return.
- **Proof.** Shoot Settings and the alert. Quote the alert title and the debug values.

## Gotchas

- `tap --label "Sign Out"` fails with "Multiple (2) accessibility elements matched" because the row and the alert button share the label and neither alert button has an identifier. Use coordinates from the tree.
- Signing out drops you to onboarding. Relaunch the fixture to continue.
- Without `-UITEST_PENDING_WRITE` sign out skips the confirmation.
- The session controls hide again after a moment of idleness. Tap the gear in the same breath as the drag, with `--wait-timeout 0`, or the reveal is gone.
- In the `settings` fixture `Done` is present but there is no stage beneath, so tapping it leaves Settings on screen.
- The `Sync now` button proves the tap, not the network. Fixture syncs never reach Google.
- `developer-tools-sync-button` sits below the fold at `@32,977` on a 402x874 screen, so it is out of `tree` and `find` reports it off-screen. `tap --id` taps the frame centre whether or not it is on screen, and a tap past the bottom edge reports success while hitting nothing. Swipe up twice first and confirm `find` prints it with no off-screen note.
- `verify.sh tree` has no enabled column. For a disabled-state proof read `verify.sh axe describe-ui` and pull each node's `enabled` field out of the JSON.
