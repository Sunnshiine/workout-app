# Meet Mode

Meet Mode runs the coach's Attempts on the day of a Meet: the Plan holds the date, federation, Attempts, Rack Heights and each Warm-up Room Plan on the phone, and the Platform reads what to warm up with, how many attempts until the platform, and how long is left to submit the next Attempt. The Sheet never holds any of it. It never picks an Attempt or estimates odds.

## Sub-features

- `meet-entry` is a text pill at the Block grid's foot beside the gear (`block-overview-meet-row`), reading `Meet`, `Meet in 28 days`, `Meet tomorrow`, or `Meet today`.
- `meet-empty` is the Plan with no Meet: `No Meet planned` over `meet-plan-start`, which creates a Meet dated today on the IPF's rules.
- `meet-plan` is the Plan: `meet-countdown`, `meet-date`, `meet-federation`, one card per Main Lift with `meet-attempt-<lift>-<opener|second|third>`, `meet-rack-<squat|bench>`, `meet-step-<lift>-<out>`, `meet-add-step-<lift>`, `meet-fill-<lift>` when the table is empty and there is an opener, `meet-lifters`, `meet-pace`, `meet-rules` (the rules sheet, each sentence with its rule number), `meet-delete`, and `meet-to-platform`.
- `meet-deck` is the Platform waiting on an Attempt: `meet-readout` (`Warm up now`, `Warm up next`, `Opener`, `Second attempt`, or `Third attempt`), the stepper `meet-attempts-out-down`, `meet-attempts-out-value`, `meet-attempts-out-up`, and `meet-change-attempt` while the rule allows a change.
- `meet-mark` is the Platform at zero attempts out: `On the platform` over `meet-mark-good`, `meet-mark-no-lift`, and `meet-not-yet`. A mark starts the Attempt Window.
- `meet-window` is the running Attempt Window: `meet-window` holds the clock, `meet-window-rule` holds the table's rule (shown in the last 15 seconds), `meet-weight-down`, `meet-weight-field`, `meet-weight-up`, `meet-submit`, `meet-undo`, and `meet-pass`. The foot stays above the keyboard.
- `meet-expired` is the window at time: `meet-table-question` over `meet-accept-table-entry`, and `meet-handed-in` when the stepper differs from the table's weight. The two read as bare weights in equal capsules, with their meaning in the VoiceOver label, in the frame Submit held. Nothing is overwritten until one is tapped, and either can be undone.
- `meet-finished` is the day done: `meet-total` with each lift's Attempts and marks, or `No total`.

## How to get to it (user POV)

- Open the Block grid from the stage header, then tap the pill beside the gear.
- From the Plan, tap `To the platform`. The screen stays awake while the Platform shows.

## Driving it with verify.sh

Preconditions:

- `verify.sh launch meet-day` landed on a `Block 27` heading with `block-overview-meet-row` on the grid. Issue #1162: on a fresh simulator `verify.sh tap` can print success and land nothing, so read the tree after a tap, and use `verify.sh axe touch -x X -y Y --down --up --delay 0.2` at the frame's centre when it did not move.

- **Real entry.** `verify.sh launch partial-block`. Tap `block-overview-meet-row`, read `No Meet planned`, tap `meet-plan-start`. `meet-countdown` reads `Today`, `meet-to-platform` is absent, and `meet-attempt-squat-opener` is a blank dashed slot. Tap it. The sheet opens with the decimal pad up and `meet-weight-save` neutral. Enter `180`, tap `meet-weight-save`, and `meet-to-platform` and `meet-fill-squat` appear. Tap `meet-fill-squat` for even steps from the bar. `meet-rack-squat` and the bench's take free text.
- **Plan.** `verify.sh launch meet-day`, tap `block-overview-meet-row`, `shot plan`. `meet-attempt-squat-opener` values `180 kilograms, 396.8 lb, planned`.
- **Warm-up room.** Tap `meet-to-platform`. `meet-readout` reads `Warm up now, 60 kilograms, 5 reps`. Tap `meet-attempts-out-down` once and it reads `Warm up next, 100 kilograms, 3 reps, in 3 attempts, about 3 min`. Three more taps reach 14 out, and it reads `Warm up now, 100 kilograms, 3 reps`.
- **Platform.** Tap `meet-attempts-out-down` to zero. `meet-readout` reads `On the platform, Squat opener, 180 kilograms`.
- **Window.** Tap `meet-mark-good`. `meet-window` values `… seconds left to submit your second attempt`. At 15 seconds left the value carries `No card means 182.5 kg` and `meet-window-rule` shows. At time, `meet-table-question` shows and `meet-accept-table-entry` reads `The table entered 182.5 kilograms`, in the frame split from `meet-submit`.
- **Next Attempt.** Tap `meet-weight-up`, tap `meet-handed-in`. `meet-readout` reads `Second attempt`, `192.5 kilograms`, and `meet-attempts-out-value` reads the lifters in flight.
- **Undo.** After a mark, tap `meet-undo`. The Platform is back on the same Attempt at zero, unmarked. After a submit, an answer at expiry, or a change, it goes back one gesture the same way, and tapping the count does not end it. An edit on the Plan does.
- **Double tap.** `meet-mark-no-lift` and `meet-submit` share a frame, so touches are held off for 0.4 s after the stage changes. Under host load two touches arrive further apart than that and the second lands, so stretch the hold in a throwaway build to prove it.
- **Headless.** `workout meet plan` and `workout meet tick` drive the same stores, as in `cli-headless.md`. `WORKOUT_NOW` moves the clock, so a window expires without waiting.
- **Proof.** The window's numeral rolls down in place, and it and its caption do not move when the rule appears, when a note arrives, or at expiry. No hue changes at any stage: the closing and expired stages read in type alone.

## Gotchas

- The window runs on the real clock in the app. A drive past expiry takes the full minute, and more under host load, so run the shots in order.
- A launch resets the Meet. `-UITEST_MEET_DAY` seeds the plan and nothing further, so every mark is driven.
- `-UITEST_MEET_WORST_CASE` seeds the longest numbers and Rack Heights a Plan holds, for break-the-UI runs.
- The keep-awake setting has nothing to read on the simulator, whose screen never sleeps. Only the code path is proven there.
- `verify.sh type` entered nothing into the decimal pad. Touch the keys by coordinate with `verify.sh axe touch`. On iPhone 17 Pro, with the sheet's pad up, `1` sits at 68,616, `8` at 200,724, and `0` at 200,778.
- At the largest type with the keyboard up, the page scrolls the field into view and the clock slides partly under the status bar. Done brings it back.
- A sheet that focuses its blank field as it presents shows no keyboard Done. Its save button stays above the pad, so nothing is lost. Tapping the field on the Platform's window does show Done.
