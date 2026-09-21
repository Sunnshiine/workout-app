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
activity outlives `stop` and sits over the top of every later shot on the shared simulator. A
relaunch is `stop` then `launch`, and it resets all state. The simulator is the
booted iPhone 17 Pro, else the newest one, which the script boots. Override with `SIM=<udid>`.

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
.claude/skills/verify/verify.sh find log-active-set-button # one line, on screen or off; exit 1 if absent; stderr says off-screen or disabled
.claude/skills/verify/verify.sh tap --id rpe-6             # or --label "Sign Out", or -x 201 -y 740
.claude/skills/verify/verify.sh hold log-active-set-button # long press, 1.2 s default
.claude/skills/verify/verify.sh type 245                   # into the focused field
.claude/skills/verify/verify.sh swipe up                   # scroll half a screen
.claude/skills/verify/verify.sh burst log-transition tap --id log-active-set-button   # one action, 12 frames over 2 s, one image
.claude/skills/verify/verify.sh axe swipe --start-x 200 --start-y 90 --end-x 200 --end-y 420 --duration 0.4   # any axe verb
```

Alert buttons have labels but no identifiers, and a label can match twice (`Sign Out` is both a
Settings row and its alert button). When `tap --label` reports multiple matches, read the frame
from `tree` and tap its center with `-x -y`.

Target elements by accessibility identifier (`tap --id`) first, by label second, by coordinates
only when the element has neither. `tap --id` polls up to 3 s for that element to be enabled and
on screen, then taps its centre; when it never gets one it exits 1 and says `off-screen` or
`disabled`. So a tap that reports success is a tap that could land. `tap --label` and `tap -x -y`
resolve no element, so they report success whatever is under the point.
After a tap, re-read the tree before asserting. `tree` has no enabled column, so prove a disabled
state with `find <id>`, which says `disabled` on stderr and still exits 0.
`-UITEST_DISABLE_ANIMATIONS` stops UIKit animations only, so a SwiftUI transition still runs for
about 850 ms after a log tap (issue 618). A state absent after one second is still absent. `burst`
is how you see a transition.

`tree` lists what is on screen and says on stderr how many elements it left out. A scrolled-out
row and the tail of the reps picker are out; a card wider than the screen is in. `find <id>`
looks everywhere, on screen or off.

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
apart, so a shot taken right on a tap can show one state and describe another. Let the transition
settle for a second, or run `burst`. After a log the rest pill counts down once a second, so the
changed lines always carry it.

## Cleanup

```bash
.claude/skills/verify/verify.sh stop     # terminates the pid this run launched; the simulator stays up
rm -rf "$WORKOUT_HOME"
```

`stop` kills only the pid recorded in `/tmp/workout-verify-<udid>/`. Set `VERIFY_RUN` and it also
refuses (exit 75) when that state dir names a different run, printing the owning run and the
`VERIFY_RUN=<owner>` override that ends it anyway. An unnamed `stop` is not gated, which is the
reason to name every run on a machine someone else is driving. It never shuts
down or erases the simulator, which other agents and `scripts/test-sim.sh` share. Evidence is
never removed, and it keeps the run name, so `diff` still answers after the app is gone. A `burst`
keeps its twelve full-size frames, about 47 MB under the git-ignored `.build/`. Delete a run's
directory yourself once its proof is filed.

## Isolation

One app instance per simulator, and one run owns it. `launch` refuses (exit 75) while a pid this
tool launched is alive on the same simulator, yours included; run `stop` or pick another `SIM`.
`stop` refuses the same way when the state dir names a run other than your `VERIFY_RUN`, so a
command that lands on the wrong simulator cannot end another agent's drive (issue 660). It can
only refuse what it can tell apart, and that cuts both ways. An unset `VERIFY_RUN` gives it
nothing to compare against, so it steps aside, and an unset `SIM` resolves onto the one shared
`iPhone 17 Pro` no matter who is driving it. Your drive is protected from a sibling only when the
sibling names its own run. Set both on every call whenever another agent might be on this
machine. Nothing locks the simulator against a test run (issue 626), so before every `launch` run
`pgrep -fl "test-sim\.sh|xcodebuild (test|build-for-testing|test-without-building)|xctrunner"`.
Read the UDID out of the match. `test-sim.sh` names it after `--sim`, and the `xcodebuild` it spawns
repeats it in `-destination platform=iOS Simulator,id=`. A match on your simulator means wait it out
or pick another `SIM`. A match with no UDID in it is a collision you cannot rule out, so treat it as
one. Two CLI drives never collide if each has its own `WORKOUT_HOME`.
