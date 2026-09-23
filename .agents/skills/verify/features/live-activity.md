# Live Activity

Logging a set starts the rest timer, and the rest timer puts the countdown, the prescription and the sets left in the Dynamic Island as a Live Activity, so the athlete reads the rest with the app closed. Developer Tools carries a Live Activity Lab that raises the same activity from a sample workout state, for design review of a variant before it ships.

## Sub-features

- `live-activity-rest-timer` raises a rest-timer activity when a set is logged, counting down outside the app.
- `live-activity-lab-start` raises a prototype activity from the Lab's sample workout state.
- `live-activity-lab-update` pushes the Lab's changed sample state into the running activity.
- `live-activity-lab-end` ends the running activity from the Lab.
- `live-activity-cleanup` leaves the simulator with no activity on it for the next drive.

## How to get to it (user POV)

- Log a set on the session stage, leave the app, and read the Dynamic Island. Long press it for the whole card.
- Open the app into the `developer-tools` fixture, then Open Live Activity Lab and Start. The longer way in, over-pulling the session header to the gear and then `settings-developer-tools-row`, is driven in `settings.md`.

## Driving it with verify.sh

Preconditions:

- Every launch in this file takes `VERIFY_LIVE_ACTIVITIES=1`, which is the only way the app requests an activity. Without it the Lab's status row reads `Live Activities disabled` and `verify.sh tap --id live-activity-lab-start-button` exits 1 saying `disabled`.
- `VERIFY_LIVE_ACTIVITIES=1 verify.sh launch session` shows the stage with `log-active-set-button` labeled `Log 237.5 × 5 @6`.

- **Log a set.** Run `verify.sh shot rest-before-log`, `verify.sh tap --id log-active-set-button`, `verify.sh shot rest-after-log`. The changed lines carry `AXGenericElement rest-pill Rest, 1 minute 57 seconds remaining` and relabel the button to `Log 252.5 × 5 @7`. That pill is the app's own; the activity is not in this tree.
- **Leave the app.** Run `verify.sh axe button home`, then `verify.sh shot rest-activity-home`. `verify.sh tree --all | grep WidgetRenderer-Activities` prints one `AXGroup jindo-container-view:1,client-identifier:com.apple.chrono.WidgetRenderer-Activities,element-identifier:activity:<uuid>` at `@37,14 329x37`, and the line under it reads `AXGenericElement regular.view Timer, 1:56`. Those two lines are the whole handle on a Live Activity from outside the app.
- **Open the card.** Run `verify.sh axe touch -x 201 -y 32 --down --up --delay 1.0`, which long presses the Dynamic Island, then `verify.sh shot rest-activity-expanded`. That point is the centre of the `@37,14 329x37` rect above, and the collapsed island sits there for every activity, so the same command opens the Lab's card later in this file. The element grows to `@14,14 374x123` and its line becomes `AXGroup regular.view Prescription 5 reps / RPE7, Rest, 1:51, Rest progress, 2 sets left`, which is every field the activity carries. It collapses again after a few seconds, so shoot before driving anything else.
- **Leave nothing behind.** Run `verify.sh stop`. It prints `terminated pid <pid>` and then `uninstalled the app, ending any Live Activity this run started`. `verify.sh tree --all | grep WidgetRenderer-Activities` now prints nothing. Run `verify.sh shot clean-after-stop`.
- **Open the Lab.** Relaunch `VERIFY_LIVE_ACTIVITIES=1 verify.sh launch developer-tools`. Run `verify.sh tap --id developer-tools-live-activity-lab-link`, then `verify.sh shot lab-enabled`. The status rows read `Live Activities enabled` over `Prototype is stopped.`, and `verify.sh find live-activity-lab-end-button` says `off-screen` and `disabled`.
- **Start the prototype.** Run `verify.sh swipe up` once, which brings `Controls` on screen, then `verify.sh tap --id live-activity-lab-start-button`. `verify.sh tree --all | grep "Prototype is"` reads `Prototype is running.`, and `find live-activity-lab-end-button` says neither note any more. Run `verify.sh axe button home`, then `verify.sh axe touch -x 201 -y 32 --down --up --delay 1.0`, then `verify.sh shot lab-activity-expanded`. The line reads `Prescription 3-5 reps / RPE6, Rest, 1:23, Rest progress, 2 sets left`, which is the Lab's sample state and not the session's.
- **Change what it renders.** Run `verify.sh tap --id WorkoutTracker` to reopen the app, then `verify.sh tap --id live-activity-lab-log-set-button`. `verify.sh find live-activity-lab-sets-done-stepper` reads `Sets, 4/5`. Run `verify.sh axe button home`, `verify.sh axe touch -x 201 -y 32 --down --up --delay 1.0`, and `verify.sh shot lab-activity-one-set`. The line's last field went from `2 sets left` to `1 set left`, so an in-app control reached a running activity.
- **End it from the Lab.** Run `verify.sh tap --id WorkoutTracker`, then `verify.sh tap --id live-activity-lab-end-button`. `verify.sh tree --all | grep "Prototype is"` reads `Prototype is stopped.` and `find live-activity-lab-end-button` says `disabled` again. Run `verify.sh axe button home`; `verify.sh tree --all | grep WidgetRenderer-Activities` prints nothing, so the Lab ends it without `stop`. Run `verify.sh shot lab-clean-home`, then `verify.sh stop`.
- **Proof.** Nine cells. `rest-before-log` and `rest-after-log` are the stage before and after the log, the second carrying `1 unsynced` in the header and the rest pill at the bottom. `lab-enabled` is the Lab with a green tick on its status row. `rest-activity-home` is the collapsed island, a black pill holding a green timer glyph and `1:55`, legible at that size. Its tree read `Timer, 1:56` a moment later, so the drawn digits and the label run a second apart on a live countdown. Read them as two clocks, not as a contradiction. `rest-activity-expanded`, `lab-activity-expanded` and `lab-activity-one-set` are the expanded card over the Home Screen, which it does not dim. The prescription sits at the top left, one line each and left-aligned over the bar's left edge: `5 reps` over `RPE7`, and `3-5 reps` over `RPE6` in the Lab. `Rest` and the countdown sit in green in the middle, over a green progress bar with the sets left at its right end. The two Lab cells differ in that last field, `2 sets left` against `1 set left`. The right of the top row stays empty, because the prescription is already on the card. Any wrapped or clipped glyph in these cells is a regression of issue 673. `clean-after-stop` is the Home Screen with the WorkoutTracker icon gone, which is what `stop` uninstalling looks like. `lab-clean-home` is the Home Screen with the icon present and nothing in the island.

## Gotchas

- Never run `verify.sh axe button lock` on a simulator anyone else will use. It wedges the screenshot pipeline. Every later `shot` returns a frame from before the lock while the tree stays live, so a drive keeps passing and files the wrong pixels (issue 674). Twelve shots across six Home Screen round trips tracked the screen exactly; one lock and the next eight were one frozen frame. Only `xcrun simctl shutdown` then `boot` clears it. The expanded island above is the bigger rendering, and it costs nothing.
- The Lock Screen asks `Allow Live Activities from WorkoutTracker?` under the first activity of each install, over `Don't Allow` and `Allow`. Answer neither. `Don't Allow` sticks to the install, and every later launch then reads `Live Activities disabled` with no flag to explain it.
- `describe-ui` answers for the frontmost app, so the activity is in the tree only while the app is not. `doctor` fails there too, saying the frontmost accessibility app is not our pid. Both are the harness, not a defect.
- A `tap --id` fired straight after `tap --id WorkoutTracker` reopens the app exited 1 twice in this drive, while `find` showed that same element enabled and on screen a second later. Re-read with `find` and repeat the tap.
- `stop` uninstalls a run that opted in, so the next `launch` reinstalls and the permission prompt comes back. A drive that never reaches `stop` leaves its activity on the simulator for whoever drives next, which is what `-UITEST_DISABLE_LIVE_ACTIVITIES` was added for (issue 657).
