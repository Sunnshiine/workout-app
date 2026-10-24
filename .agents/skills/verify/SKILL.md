---
name: verify
description: Drive the WorkoutTracker iOS app on the simulator (and the headless `workout` CLI) the way a user would and capture proof. Use before claiming any UI or store behavior works, when a UI test is red and you need to see the screen, and for bug reproductions.
---

# Verify WorkoutTracker

Two user surfaces. The iPhone app on the simulator is primary. The `workout` CLI runs the same
stores headless against a workbook file and is the fast path for store and sync behavior that has
no UI question attached. Everything below runs from the repo root. The helper is
`.agents/skills/verify/verify.sh` (call it `verify.sh` here). `.claude/skills/verify` is a tracked
symlink to this directory, so there is one copy and either path works. Read `features/README.md`
and the matching feature file before driving; the map lists every entry point a proof must cover.

## Launch

```bash
export SIM=$(xcrun simctl create LANE_NAME "iPhone 17 Pro" com.apple.CoreSimulator.SimRuntime.iOS-27-0)   # once
.agents/skills/verify/verify.sh build              # xcodebuild build, about 10 s warm, 2 min cold
.agents/skills/verify/verify.sh launch session     # install + launch into a fixture, returns when the tree answers
```

Fixtures: `session` (Block 27 W1 D1, Back Squat then BB RDL, 5 pending sets), `settings`,
`onboarding` (sheet picker with a stale seeded Block), `long-session` (8 exercises),
`partial-block` (Block Overview, some sessions not uploaded), `completed-open-exercises`
(completion stage), `developer-tools`. Extra `-UITEST_*` arguments pass through, for example
`launch settings -UITEST_PENDING_WRITE`. [launch-flags.md](launch-flags.md) lists every flag and
what it does. `launch session -UITEST_APPEARANCE dark` renders Night
without changing the simulator's appearance, and `light` renders Day. Any other value, `night`
included, makes the app exit, and `launch` prints the fatal error naming the values. Every launch
adds `-UITEST_FIXTURE -UITEST_DISABLE_ANIMATIONS -UITEST_DISABLE_LIVE_ACTIVITIES`, so the app runs on an in-memory store with a faked sign-in and
never touches Google. Live Activities are off because a rest-timer activity outlives `stop` and
sits over the top of every later shot on the shared simulator.
`VERIFY_LIVE_ACTIVITIES=1 verify.sh launch session` drops that one flag, so the rest timer and the
Live Activity Lab work and every shot of that run may carry the activity overlay. `stop` uninstalls
such a run, which is what ends the activity. Drive it from `features/live-activity.md`. A
relaunch is `stop` then `launch`, and it resets all state. Every command that touches a simulator
needs `SIM`, the UDID of your own simulator. Without it, the command exits 2 and prints the
`simctl create` line above. There is no default, because the stock iPhone 17 Pro is shared (issue
660). `launch` boots the simulator when it is shut down and waits for the boot to finish before it
installs the app. When the lane is done, `xcrun simctl shutdown "$SIM" && xcrun simctl delete "$SIM"`
removes its simulator.

`launch` prints the app it installed:

```
launched session as pid 4121 on 25A4832B-C8F9-455B-8439-1E40358BDCC0
app 804e750cad00 commit ea5af074-dirty (this worktree's build)
evidence /Users/me/workout-app/.claude/work/evidence/env-verify-identity/issue-536
```

The hash covers every file in the bundle (the code, the widget extension, assets, and
`Info.plist`), so two apps are the same app when their hashes match. `build` stamps the commit into the bundle, with `-dirty` when
`App/`, `Sources/WorkoutTracker/`, `WorkoutShared/`, `WorkoutWidgets/`, the project, or the package
files had uncommitted changes. An app whose bytes no stamp describes reads `commit unknown (not
built by verify.sh)`. When a lock, boot, app-cache build, or no-built-app refusal leaves another
app installed, the refusal ends with `app on <udid> unchanged:`, the app still there, and the app
the launch wanted. When `simctl install` leaves bytes that differ from the build, `install` and
`launch` say so, uninstall the app, and install it once more. When the bytes still differ, or
`simctl install` fails, they exit 70 and name both apps.

### Control and head on one simulator

To run a control commit's app and then this worktree's on one simulator (`install <commit>`,
`launch --at <commit>`, the shared app cache), read [control-and-head.md](control-and-head.md).

For the CLI there is no server. Build once, then every drive gets its own home:

```bash
swift build --product workout
export WORKOUT_HOME=$(mktemp -d) && .build/debug/workout init --scenario fresh-block
```

## Doctor

```bash
.agents/skills/verify/verify.sh doctor
```

Read-only. Run it after every `launch`, and again whenever a tap does nothing or the tree looks
wrong. Every line reads `ok` or `FAIL`, and any `FAIL` exits non-zero, so `doctor && <drive>` is a
safe chain. The installed-app line hashes the app on the simulator. It reads `ok` when that app is
this worktree's build, or a cached build that still matches its cache entry. Otherwise it names
both apps, as in `FAIL installed app 804e750cad00 commit ea5af074 (an earlier build of this
worktree) is not this worktree's build, app 033a3ca3fcdb commit ea5af074-dirty (run: verify.sh
install)`. Two builds of the same source can differ in bytes, so after a rebuild with no source
change this line can still FAIL until the next `install`. For this worktree's build it also fails
sources newer than the app, which means build before trusting anything. A last line reading
`FAIL AutomaticMinimizationEnabled is 1` means a focused field shows no software keyboard (issue
700); the next `launch` resets it. An empty tree on a healthy pid means the simulator's accessibility bridge is wedged;
`xcrun simctl shutdown <udid>` then relaunch.

## Drive

```bash
.agents/skills/verify/verify.sh tree                       # what is on screen: role  id  label  value  @x,y wxh
.agents/skills/verify/verify.sh tree --all                 # plus what is scrolled out of view, and unnamed layout groups
.agents/skills/verify/verify.sh find log-active-set-button # one line, on screen or off; exit 1 if absent; stderr says off-screen, clipped, or disabled
.agents/skills/verify/verify.sh tap --id rpe-6             # or --label "Sign Out", or -x 201 -y 740
.agents/skills/verify/verify.sh hold log-active-set-button # long press, 1.2 s default
.agents/skills/verify/verify.sh type 245                   # into the focused field
.agents/skills/verify/verify.sh swipe up                   # scroll half a screen
.agents/skills/verify/verify.sh burst log-transition tap --id log-active-set-button   # one action, 12 frames over 2 s, one image
.agents/skills/verify/verify.sh axe swipe --start-x 200 --start-y 90 --end-x 200 --end-y 420 --duration 0.4   # any axe verb
```

`tree` prints an element with neither an identifier nor a label with empty id and label columns
when it has a value or a control, text, or image role, so an unnamed field is visible as unnamed,
not missing. It hides unnamed layout groups with no value and off-screen elements, and says on
stderr how many of each it hid; `tree --all` prints them too. `find`, `tap`, and `hold` never
resolve an unnamed element.

Any AXe keyboard event, `type` included, hides the software keyboard in the running app until its
next launch (issue 700). After `type` and after `axe key`, `key-sequence`, `key-combo`, or `type`,
`verify.sh` resets the simulator preference that would keep it hidden after that launch too, says
so on stderr, and exits with AXe's status. A raw AXe call, an XCUITest run, or an older drive can
still leave that preference on, so `launch` reads it and resets it before it starts the app, and
says so on stderr.

Target elements by accessibility identifier (`tap --id`) first, by label second, by coordinates
only when the element has neither. Alert buttons have labels but no identifiers. Read
[tap.md](tap.md) for what `tap` checks before it taps, how long that takes, and what each refusal
(`off-screen`, `clipped`, `disabled`, `covered`) and `not checked for cover:` mean.

After a tap, re-read the tree before asserting. `tree` has no enabled column, so prove a disabled
state with `find <id>`, which says `disabled` on stderr and still exits 0.

What still moves under `-UITEST_DISABLE_ANIMATIONS`, and what a `burst` can and cannot show, is in
[motion.md](motion.md). Read it before you prove a transition with `burst`.

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
VERIFY_RUN=issue-536 .agents/skills/verify/verify.sh launch session   # names the run; prints its directory
.agents/skills/verify/verify.sh shot 01-before                        # 01-before.png + 01-before.tree.txt
.agents/skills/verify/verify.sh tap --id log-active-set-button
.agents/skills/verify/verify.sh shot 02-after-log                     # those two files, then the lines that changed since 01-before
.agents/skills/verify/verify.sh diff 01-before 02-after-log           # the same comparison for any two shots of the run
.agents/skills/verify/verify.sh sheet                                 # every shot of the run, 12 to an image, numbered and labelled
.agents/skills/verify/verify.sh crop 02-after-log rest-pill           # the pill at the shot's own pixels; or crop NAME X Y W H
```

Artifacts land in `<main checkout>/.claude/work/evidence/<branch>/<run>/`, so they survive `stop`
and the removal of the worktree. Any character of the branch outside letters, digits, `.`, `_`,
and `-` becomes `-`, and a detached worktree uses `detached-<directory>`. `VERIFY_EVIDENCE=<dir>`
puts runs in `<dir>/<run>/` instead. Each `launch` appends its app line, simulator, and worktree to
the run's `launches.txt`, and each refused `launch` its refusal, so the evidence names its binary
after the simulator is gone. `launch` names the run from
`VERIFY_RUN` (default a timestamp), and every later command finds it without being told. A bare
`launch` starts a new run, so give the same `VERIFY_RUN` to every `launch` of one task. A proof
captures the action and the resulting state, not just the final screen. Shoot before, drive, shoot
after. The second `shot` prints the tree lines that changed with positions ignored, so a row that
only moved is not a change; quote those lines verbatim. Prove side effects alongside the screen.
After a log under `-UITEST_OFFLINE`, the header reads `Sync status: 1 unsynced` and the branch
gains a `Set 1, 237.5x5@6` button. For store or sync effects with no UI question, run the same operation through the CLI and
quote its JSON, or run the covering `swift test --filter` suite. The fixture sheet is a local workbook,
and a log flushes into it as it would into the coach's Sheet. `-UITEST_OFFLINE` makes it read as
Offline after the boot, so a log stays queued. A green flush in fixture mode proves the queue and the cells, not Google. Exercise the real path (taps, the log button, the CLI verbs), never a `-UITEST_*` flag that
jumps to the end state.

Finish every UI proof with `sheet` and Read every image it prints, one per 12 shots. The read is
owed for one shot too, because nothing else looks at the pixels. Report what you see by cell
number, and say anything the tree cannot show. Overlap, colour, clipping, an element under the
status bar. Give that read to your strongest model. A smaller one read every string on a 12-up
sheet and still missed a layout defect on it. A full shot reads at about 0.76x. To read a detail,
`crop` it by id, which takes 8 points around the element, or by the points of a tree line, then
Read the path it prints. The crop is the shot's own pixels, and it is never on a sheet. A shot's
PNG and its tree are captured about 0.2 s apart, so a shot taken right on a tap can show one state
and describe another. Wait a second after a tap before a shot, or run `burst`. After a log the
rest pill counts down once a second, so the changed lines always carry it.

`shot` refuses a PNG byte-identical to the run's newest shot, a retake of the same name included,
while the tree changed. It saves nothing, prints the changed lines, and exits 70.

To put shots or a take into a PR body, use the `pr-evidence` skill.

## Motion

Under `-UITEST_DISABLE_ANIMATIONS` a slide, a fade, or a fly-in is one cut, so `shot` and `burst`
cannot show it. Prove a change to anything that moves with a measured take that has motion on.
Read [motion.md](motion.md) before `launch --animated`, `record`, `cardframe.py`, or `cardstill.py`:
it holds the commands, the exit codes, and how to read `still=`, `box=`, `look=` and `edges=`.

## Cleanup

```bash
.agents/skills/verify/verify.sh stop     # terminates the pid this run launched; the simulator stays up
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
keeps its twelve full-size frames, about 47 MB under the git-ignored `.claude/work/`. Delete a run's
directory yourself once its proof is filed.

## Isolation

One app instance per simulator, and one run owns it. Read [isolation.md](isolation.md) when a command
exits 75, when another agent may be driving or testing on this machine, or when a claim waits for the
host.

## Changing this skill

After an edit to anything in this skill, `scripts/contact-sheet.swift`, or `scripts/sim-lock.sh`, run
`uv run --locked python -m unittest discover -s .agents/skills/verify/tests`, the command
`.github/workflows/verify-tools.yml` runs. The motion tests in it need `ffmpeg` and `ffprobe` on PATH. Also run
every `scripts/tests/host-admission*.test.sh` after an edit to `verify.sh`, a `verify-*.sh` helper,
`scripts/sim-lock.sh`, or `scripts/build-slot.sh`, and `scripts/contact-sheet.test.sh` after an edit to the tiler. CI runs
every script test through `.github/workflows/script-tests.yml`.
