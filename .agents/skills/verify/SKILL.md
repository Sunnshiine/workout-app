---
name: verify
description: Drive the WorkoutTracker iOS app on the simulator (and the headless `workout` CLI) the way a user would and capture proof. Use before claiming any UI or store behavior works, when a UI test is red and you need to see the screen, and for bug reproductions.
---

# Verify WorkoutTracker

Two user surfaces. The iPhone app on the simulator is primary. The `workout` CLI runs the same
stores headless against a workbook file and is the fast path for store and sync behavior that has
no UI question attached. Everything below runs from the repo root. The helper is
`.claude/skills/verify/verify.sh` (call it `verify.sh` here). Read `features/README.md` and the
matching feature file before driving; the map lists every entry point a proof must cover.

## Launch

```bash
.claude/skills/verify/verify.sh build              # xcodebuild build, about 10 s warm, 2 min cold
.claude/skills/verify/verify.sh launch session     # install + launch into a fixture, returns when the tree answers
```

Fixtures: `session` (Block 27 W1 D1, Back Squat then BB RDL, 5 pending sets), `settings`,
`onboarding` (sheet picker with a stale seeded Block), `long-session` (8 exercises),
`partial-block` (Block Overview, some sessions not uploaded), `completed-open-exercises`
(completion stage), `developer-tools`. Extra `-UITEST_*` arguments pass through, for example
`launch settings -UITEST_PENDING_WRITE`. Every launch adds `-UITEST_FIXTURE
-UITEST_DISABLE_ANIMATIONS -UITEST_DISABLE_LIVE_ACTIVITIES`, so the app runs on an in-memory store
with a faked sign-in and never touches Google. Live Activities are off because a rest-timer
activity outlives `stop` and sits over the top of every later shot on the shared simulator.
`VERIFY_LIVE_ACTIVITIES=1 verify.sh launch session` drops that one flag, so the rest timer and the
Live Activity Lab work and every shot of that run may carry the activity overlay. `stop` uninstalls
such a run, which is what ends the activity. Drive it from `features/live-activity.md`. A
relaunch is `stop` then `launch`, and it resets all state. The simulator is the one
`SIM=<udid>` names, else the booted iPhone 17 Pro, else the newest one, else one it creates on
iOS 27.0 with `scripts/ensure-simulator.sh`. `launch` boots it when it
is shut down and waits for the boot to finish before it installs the app.

For the CLI there is no server. Build once, then every drive gets its own home:

```bash
swift build --product workout
export WORKOUT_HOME=$(mktemp -d) && .build/debug/workout init --scenario fresh-block
```

## Doctor

```bash
.claude/skills/verify/verify.sh doctor
```

Read-only. Run it after every `launch`, and again whenever a tap does nothing or the tree looks
wrong. Every line reads `ok` or `FAIL`, and any `FAIL` exits non-zero, so `doctor && <drive>` is a
safe chain. The commonest `FAIL` is sources newer than the app, which means build before trusting
anything. An empty tree on a healthy pid means the simulator's accessibility bridge is wedged;
`xcrun simctl shutdown <udid>` then relaunch.

## Drive

```bash
.claude/skills/verify/verify.sh tree                       # what is on screen: role  id  label  value  @x,y wxh
.claude/skills/verify/verify.sh tree --all                 # plus what is scrolled out of view
.claude/skills/verify/verify.sh find log-active-set-button # one line, on screen or off; exit 1 if absent; stderr says off-screen, clipped, or disabled
.claude/skills/verify/verify.sh tap --id rpe-6             # or --label "Sign Out", or -x 201 -y 740
.claude/skills/verify/verify.sh hold log-active-set-button # long press, 1.2 s default
.claude/skills/verify/verify.sh type 245                   # into the focused field
.claude/skills/verify/verify.sh swipe up                   # scroll half a screen
.claude/skills/verify/verify.sh burst log-transition tap --id log-active-set-button   # one action, 12 frames over 2 s, one image
.claude/skills/verify/verify.sh axe swipe --start-x 200 --start-y 90 --end-x 200 --end-y 420 --duration 0.4   # any axe verb
```

Target elements by accessibility identifier (`tap --id`) first, by label second, by coordinates
only when the element has neither. Alert buttons have labels but no identifiers. `tap --id` polls
up to 3 s for that element to be enabled, on screen, and with its centre inside the frame of every
element that contains it, then taps that centre. A container with a zero width or height holds no
point, so it is skipped. The keyboard toolbar wraps `Done` in a 0x0 group. When `tap --id` never
gets such a hit it exits 1 and says `off-screen`, `clipped`, or `disabled`. A `clipped` note names
the container whose frame misses the centre, such as the RPE track. So a tap that reports success
hit an element that is on screen, enabled, and inside every container that clips it.

`tap --label` resolves its element through the tree the same way, with the same poll and the same
notes. It matches the whole label as `tree` prints it, case included. When a control and a text
carry the label, it taps the control. When more than one is left, it exits 1 and lists each with
its centre. With the sign-out alert up, `tap --label "Sign Out"` lists the Settings row and the
alert's own button, so tap the alert's button at its centre with `-x -y`. No check sees an alert
or sheet over an element, so a tap on the Settings row behind that alert still reports success.
`tap -x -y` resolves no element, so it still reports success whatever is under the point.

After a tap, re-read the tree before asserting. `tree` has no enabled column, so prove a disabled
state with `find <id>`, which says `disabled` on stderr and still exits 0.
`-UITEST_DISABLE_ANIMATIONS` stops UIKit animations and clears the animation on every SwiftUI
transaction in the main window. Bursts and screen recordings under it, each checked against a run
without it that moved, show one cut from the old screen to the new for these: a log with the
weight keyboard closed, a skip's commit, a Superset log, the Move On celebration opening and
closing, and the pairing state inside the queue sheet. The tapped button can show its pressed
colour for up to about 90 ms before that cut. A Superset log's retiring card never draws. After a
log the sync pill lands a frame or two after the card, reads `Syncing`, then `1 unsynced`, and
moves everything below it down about 20 points, the rest pill included. Two of the five log bursts
saved for issues 618 and 696 caught the new card with no sync pill.

Some states still change under the flag (issue 739). The rest pill's countdown and progress line
change on their own while rest runs. Every rest after the first on the Session screen starts with
the rest pill about 3% larger and brighter for about 150 ms; a burst caught that on a log while
rest ran. Each second from `0:05` to `0:00` the countdown digits grow about 3% for about 230 ms. A
skip hold's fill jumps to a full `Skipped` 250 ms into the press, and the skip lands about 900 ms
in, so a shot in between shows a skip that has not happened. In the history sheet the Volume chip
still fades for about 250 ms after a tap (issue 739).

`burst` takes its first frame before the drive command runs and the other eleven after it returns,
timed from the return. In the issue 696 runs the first frame came 1.3 to 8.7 s before it, and a
`hold` spends its whole press inside the drive, so a burst never shows the middle of a hold. After
the return, frames land about 200 ms apart, more than 2 s apart on a busy simulator, and the first
lands 140 to 750 ms after it. A burst that shows only a before and an after says nothing about a
state shorter than those gaps, and a 3% change is easy to miss on the tile, so read the full-size
frames in `<name>.burst/`. Any other path is unproved under the flag. A state an action has not
caused within one second will not appear later. `burst` shows frame by frame what an action
changed.

`tree` lists what is on screen and says on stderr how many elements it left out. A scrolled-out
row and the tail of the reps picker are out; a card wider than the screen is in. `find <id>`
looks everywhere, on screen or off. `tree` measures against the screen alone, so it still lists a
rail chip outside its track; `find` on that chip says `clipped`.

The driver is AXe, bundled with XcodeBuildMCP 2.7.0 and installed on first use into
`.build/verify/node_modules` (about 20 s, gitignored). Older XcodeBuildMCP builds fail on Xcode 27
with "SimulatorKit.framework ... does not exist".

CLI drive is the binary itself. Capture stdout, stderr, and the exit code of each command.

## Evidence

```bash
VERIFY_RUN=issue-536 .claude/skills/verify/verify.sh launch session   # names the run; prints its directory
.claude/skills/verify/verify.sh shot 01-before                        # 01-before.png + 01-before.tree.txt
.claude/skills/verify/verify.sh tap --id log-active-set-button
.claude/skills/verify/verify.sh shot 02-after-log                     # those two files, then the lines that changed since 01-before
.claude/skills/verify/verify.sh diff 01-before 02-after-log           # the same comparison for any two shots of the run
.claude/skills/verify/verify.sh sheet                                 # every shot of the run, 12 to an image, numbered and labelled
```

Artifacts land in `.build/verify/evidence/<run>/` and survive `stop`. `launch` names the run from
`VERIFY_RUN` (default a timestamp), and every later command finds it without being told. A bare
`launch` starts a new run, so give the same `VERIFY_RUN` to every `launch` of one task. A proof
captures the action and the resulting state, not just the final screen. Shoot before, drive, shoot
after. The second `shot` prints the tree lines that changed with positions ignored, so a row that
only moved is not a change; quote those lines verbatim. Prove side effects alongside the screen.
After a log, the header reads `Sync status: 1 unsynced` and the branch gains a `Set 1, 237.5x5@6`
button. For store or sync effects with no UI question, run the same operation through the CLI and
quote its JSON, or run the covering `swift test --filter` suite. The fixture sheets client accepts
every write and never reaches the network, so a green flush in fixture mode proves the queue, not
Google. Exercise the real path (taps, the log button, the CLI verbs), never a `-UITEST_*` flag that
jumps to the end state.

Finish every UI proof with `sheet` and Read every image it prints, one per 12 shots. The read is
owed for one shot too, because nothing else looks at the pixels. Report what you see by cell
number, and say anything the tree cannot show. Overlap, colour, clipping, an element under the
status bar. Give that read to your strongest model. A smaller one read every string on a 12-up
sheet and still missed a layout defect on it. A shot's PNG and its tree are captured about 0.2 s
apart, so a shot taken right on a tap can show one state and describe another. Wait a second
after a tap before a shot, or run `burst`. After a log the rest pill counts down once a second, so
the changed lines always carry it.

`shot` refuses a PNG byte-identical to the run's newest shot, a retake of the same name included,
while the tree changed. It saves nothing, prints the changed lines, and exits 70.

## Cleanup

```bash
.claude/skills/verify/verify.sh stop     # terminates the pid this run launched; the simulator stays up
rm -rf "$WORKOUT_HOME"
```

`stop` kills only the pid recorded in `/tmp/workout-verify-<udid>/`. Set `VERIFY_RUN` and it also
refuses (exit 75) to act on a different run's app, printing the owning run and the
`VERIFY_RUN=<owner>` override that ends it anyway. That covers an app that is still alive, and a
dead one launched under `VERIFY_LIVE_ACTIVITIES=1`, which `stop` would still uninstall. Nothing
else is refused, so whichever run's `stop` comes next deletes any other dead app's pid and args.
An unnamed `stop` is not gated, which is the
reason to name every run on a machine someone else is driving. A run launched under
`VERIFY_LIVE_ACTIVITIES=1` is uninstalled as well as terminated, because a Live Activity belongs to
the app rather than to its process and uninstalling is the only lever on one from outside the app.
`stop` refuses (exit 75) to uninstall while a `scripts/test-sim.sh` run holds the simulator, because
the uninstall would remove the app under test. `stop` never shuts down or erases the simulator, which
other agents and `scripts/test-sim.sh` share. Evidence is
never removed, and it keeps the run name, so `diff` still answers after the app is gone. A `burst`
keeps its twelve full-size frames, about 47 MB under the git-ignored `.build/`. Delete a run's
directory yourself once its proof is filed.

## Isolation

One app instance per simulator, and one run owns it. `launch` refuses (exit 75) while a pid this
tool launched is alive on the same simulator, yours included; run `stop` or pick another `SIM`.
`stop` refuses the same way when it would act on another run's app, so a
command that lands on the wrong simulator cannot end another agent's drive (issue 660). It can
only refuse what it can tell apart, and that cuts both ways. An unset `VERIFY_RUN` gives it
nothing to compare against, so it steps aside, and an unset `SIM` resolves onto the one shared
`iPhone 17 Pro` no matter who is driving it. Your drive is protected from a sibling only when the
sibling names its own run. Set both on every call whenever another agent might be on this
machine. `launch`, `shot`, and `burst` refuse (exit 75) while a `scripts/test-sim.sh` run holds the
simulator. `test-sim.sh` refuses the same way while a run's app is alive on it. Each refusal names
the holder and its pid. The lock sees only `scripts/test-sim.sh`, so an XcodeBuildMCP `test_sim` or
a raw `xcodebuild test` on the same UDID is invisible to it. Before a `launch` when another agent
may be testing, run `pgrep -fl "id=<udid>"`. Two CLI drives never collide if each has its own
`WORKOUT_HOME`.
