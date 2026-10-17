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

```bash
VERIFY_RUN=ui12-control verify.sh launch --at 9a72f8dc session  # builds 9a72f8dc into the app cache once, installs, launches
verify.sh stop
verify.sh install                                              # the head: this worktree's build, replacing the control
VERIFY_RUN=ui12-head verify.sh launch session
```

`install <commit>` and `launch --at <commit>` build that commit in a scratch worktree the first
time any worktree asks, and every later call reuses the build. Give that first call a 10 minute
timeout. Two lanes that ask at once build it once, and the second says it is waiting. A build that
was killed resumes in its scratch worktree on the next call for that commit, and a call for any
other commit removes it. A bare `launch` refuses (exit 65) to replace an installed
cached build, so a head phase that skipped `install` stops instead of running the control. The cache
is `<main checkout>/.claude/work/app-cache/<sha>/`. Nothing prunes it; remove an entry by hand, and
it costs one rebuild.

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
.agents/skills/verify/verify.sh tree --all                 # plus what is scrolled out of view, and elements with no id or label
.agents/skills/verify/verify.sh find log-active-set-button # one line, on screen or off; exit 1 if absent; stderr says off-screen, clipped, or disabled
.agents/skills/verify/verify.sh tap --id rpe-6             # or --label "Sign Out", or -x 201 -y 740
.agents/skills/verify/verify.sh hold log-active-set-button # long press, 1.2 s default
.agents/skills/verify/verify.sh type 245                   # into the focused field
.agents/skills/verify/verify.sh swipe up                   # scroll half a screen
.agents/skills/verify/verify.sh burst log-transition tap --id log-active-set-button   # one action, 12 frames over 2 s, one image
.agents/skills/verify/verify.sh axe swipe --start-x 200 --start-y 90 --end-x 200 --end-y 420 --duration 0.4   # any axe verb
```

`tree` prints only named elements and says on stderr how many it hid. An element with neither an
identifier nor a label still exists; `tree --all` prints it with empty id and label columns.

Any AXe keyboard event, `type` included, hides the software keyboard in the running app until its
next launch (issue 700). After `type` and after `axe key`, `key-sequence`, `key-combo`, or `type`,
`verify.sh` resets the simulator preference that would keep it hidden after that launch too, says
so on stderr, and exits with AXe's status. A raw AXe call, an XCUITest run, or an older drive can
still leave that preference on, so `launch` reads it and resets it before it starts the app, and
says so on stderr.

Target elements by accessibility identifier (`tap --id`) first, by label second, by coordinates
only when the element has neither. Alert buttons have labels but no identifiers. `tap --id` polls
up to 3 s for that element to be enabled, on screen, and with its centre inside the frame of every
element that contains it. A container with a zero width or height holds no point, so it is skipped.
The keyboard toolbar wraps `Done` in a 0x0 group. Last, `tap --id` asks axe what is on top at that
centre. The answer must belong to the app in front and be the element or something inside its
frame, and then it taps that centre. A system prompt over the app is covered. The pid file that
`launch` writes decides when this check runs:

- While the app `launch` started is in front, the check runs.
- While another pid is in front, the check stands aside and the tap goes by the tree alone. `tap`
  prints `not checked for cover:` on stderr with both pids. This covers the Home Screen, another
  app, and the app relaunched under a new pid, which `doctor` flags.
- With no pid file, after `stop` or for an app `launch` did not start, the check runs for whatever
  is in front. On the Home Screen axe's point read can name a neighbouring icon, and then the tap
  is refused as `covered`.

That second read makes a tap that lands take about 3 s, against about 2 s without it.

When `tap --id` never gets a hit that passes every check, it exits 1 and says `off-screen`,
`clipped`, `disabled`, or `covered`. A refusal takes 4 s or more, because it polls the full 3 s and
then reads once more. A `clipped` note names the container whose frame misses the centre, such as
the RPE track. A `covered` note names what is on top instead, such as an alert's backdrop, or
whatever took the place of an element that went away after the tree was read. So a tap that reports
success aimed at an element that was on screen, enabled, inside every container that clips it, and
on top, unless it printed `not checked for cover:`. The tap lands up to about a second after that
last look, and an element that leaves in that second still reports success. So prove a tap by
what it changed.

`tap --label` resolves its element through the tree the same way, with the same poll and the same
notes. It matches the whole label as `tree` prints it, case included. When a control and a text
carry the label, it taps the control. When more than one is left, it exits 1 and lists each with
its centre. With the sign-out alert up, `tap --label "Sign Out"` lists the Settings row and the
alert's own button, so tap the alert's button at its centre with `-x -y`. `tap -x -y` resolves no
element, so it still reports success whatever is under the point.

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
in, so a shot in between shows a skip that has not happened. The Log capsule jumps to 0.97 scale at
touch-down and sits there until the finger lifts or the skip lands. In the history sheet the Volume chip
still fades for about 250 ms after a tap (issue 739).

`burst` takes its first frame before the drive command runs and the other eleven after it returns,
timed from the return. In the issue 696 runs the first frame came 1.3 to 8.7 s before it, and a
`hold` spends its whole press inside the drive, so a burst never shows the middle of a hold. After
the return, frames land about 200 ms apart, more than 2 s apart on a busy simulator, and the first
lands 140 to 750 ms after it. A burst that shows only a before and an after says nothing about a
state shorter than those gaps, and a 3% change is easy to miss on the tile, so read the full-size
frames in `<name>.burst/`. Any other path is unproved under the flag; prove it under Motion below. A state an action has not
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
After a log, the header reads `Sync status: 1 unsynced` and the branch gains a `Set 1, 237.5x5@6`
button. For store or sync effects with no UI question, run the same operation through the CLI and
quote its JSON, or run the covering `swift test --filter` suite. The fixture sheet is a local workbook
that reads as Offline after the boot, so a log stays queued, unless `-UITEST_PENDING_WRITE` keeps
it reachable. A green flush in fixture mode proves the queue and the cells, not Google. Exercise the real path (taps, the log button, the CLI verbs), never a `-UITEST_*` flag that
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

## Motion

Under `-UITEST_DISABLE_ANIMATIONS` a slide, a fade, or a fly-in is one cut, so `shot` and `burst`
cannot show it. Prove a change to anything that moves with a measured take that has motion on.

```bash
VERIFY_RUN=card-in verify.sh launch --animated session                 # same lock, pid and install path; motion on
verify.sh record log --tail 3 -- tap --id log-active-set-button          # log.mp4, log.take, log.end.txt
verify.sh stop && verify.sh record appear -- launch --animated session   # a first appear: the launch is the drive
uv run .agents/skills/verify/motion/cardframe.py <run dir>/appear.mp4    # the Active Set Card's box and look per frame
uv run .agents/skills/verify/motion/cardstill.py --control <a commit whose card moves>   # 15 min
```

`record` first waits while the 1-minute load is over `WORKOUT_LOAD_LIMIT` (50), because a loaded host
films a move as a cut. A take whose load ends over it is INVALID. It drives once the recorder
is capturing and stops it with SIGINT. Exit 0 is a VALID take. Exit 3 is INVALID, files kept, reasons
on stderr. Exit 70 means the recorder or ffprobe failed, or the screen size or the card's frame could
not be read from the accessibility tree after the take, and nothing is kept, a VALID take included.
Exit 75 means nothing ran.
The recorder writes a frame only when the screen changes, so a still screen is one frame. A take is
also INVALID when the screen never changed after the drive began, or, with no drive, never changed at
all. Any change counts, the rest pill's countdown included, so `VALID` says the recorder was capturing.
It does not say the drive did anything. While the rest pill counts down, a drive that changes nothing
is `VALID`. `record` also saves the tree at the take's end as `NAME.end.txt`; read it to see that the
drive landed. Whether the card moved is `still=`'s answer. `cardframe.py` is the one frame metric, and it
times frames by their own pts, because ffmpeg's clock puts simctl frames about 0.8 s early. It reads
two things: the card's box, from its edges, and its look, the luminance inside the settled box.
A neighbour such as the rest pill joins the box across a gap only while the pair fits the
height of the `card_pt=` frame `record` stamps from the accessibility tree, and an unbroken run counts at
any height, so a card that shrinks during the take reads its whole range. `still=no` means the box or the
look moved, and `box=` and `look=` say which, on a take whose INVALID reasons, if any, only hide motion
(load, a short window), animations on or off. `still=yes` needs `edges=full` and a card where the tree
puts it: nothing moved on a VALID take with animations on, the card's edges were read from the window's
first frame, and the box sits on the `card_pt=` frame: its middle within 8 pt and its height within 24 pt.
A box still moving in its last frame is held to its height and x only, because the tree is read after the
recorder stops and holds where the card was going. `still=unknown` covers the rest: nothing moved but the take is INVALID,
has animations off, or has `edges=partial`; or something moved on a take INVALID for any other reason,
such as a launch with no fade from black. A take whose tree held no `active-set-card`, or whose box is not
where the tree put it, exits 1 with `no card:` and its reason. A label that swaps in one frame reads
`look=cut` and stays still. A take that presses the Log capsule reads `look=changed` from the press's
0.97 scale, so judge the card there by `box=`. A launch take's window opens at the end of iOS's fade-in, the full-screen
frames in the 0.5 s after the screen leaves black; any later frame that changes three quarters of the
screen makes the take INVALID. So first-appear motion that ends inside that fade is invisible to a launch
take. From the fade's end the window must watch 1.5 s or the take is INVALID. `cardstill.py` prints PASS
only when the control commit moved the card on one of its eight takes and the head held it still on all
eight. Each take's `.end.txt` must show where its drive leads (the next Set active, the review open, then
closed, the partner in front, the rest pill gone), or the take is INVALID.

Judge a take by its reads, never by its numbers. The contract is the exit codes, `VALID` or `INVALID`,
`still=`, `box=`, `look=` and `edges=`. `cardframe.py` exits 0 when it measured, 1 with no card, and 3
when the take is INVALID or animations are not on. A first-appear launch take with `--animated` reads
as follows:

- A card that slides in reads `still=no box=changed look=changed edges=partial`.
- A card that fades in place reads `still=no look=changed edges=partial`. Its `box=` can read `changed`
  by under 1 pt, as two of r6's five fade takes did. `look=changed` decides `still=no` either way, so for
  a fade read `look=`, not `box=`. `cardstill.py` judges the box alone, so there a box that changed by
  over 0.5 pt is a FAIL.
- A card already in place when the window opens reads `still=yes box=still edges=full`.

Without `--animated`, the sliding card reads `still=unknown` and `cardframe.py` exits 3, because
animations off hides the slide.

The numbers vary with the host's load and the build, so take them as rough examples, not limits. They
come from one Mac at load 4 to 12, on two builds of the app after the UI refactor stack (717737ad and
8e495e47). With the default 2 s `--tail`, the launch window watched about 2.2 to 2.9 s. A card sliding
in 300 pt from the right read `worst_edge_range` about 13 to 18 and `look_ms` about 1150. A fade read
`look_ms` just under 1000. At load 34 to 38 the same slide read `worst_edge_range` 1.7 on a VALID take,
with the reads above. A take with those reads is read correctly even when its numbers fall outside these.
After an edit to `take.py` or `motion/`, also run `uv run .agents/skills/verify/tests/test_motion.py`.

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

One app instance per simulator, and one run owns it. `launch`, `install`, and `scripts/test-sim.sh`
refuse (exit 75) while another run's app is alive on the same simulator and that run's lease is live:
some command for the run came in the last `WORKOUT_LEASE_MINUTES` (60). Every command but `build`,
`install`, `diff`, `sheet`, and `crop` renews the lease. A command with no `VERIFY_RUN` keeps a live lease
going but cannot revive an expired one. A run quiet for longer counts as abandoned. The next claim
reclaims the simulator, stops the run's app, and says so. From then on every command for the
reclaimed run but `build`, `install`, `diff`, `sheet`, and `crop`, `stop` included, exits 75 naming who
reclaimed it and when, until the run launches again. A command with no `VERIFY_RUN` acts for the
run that launched last on the simulator, so after a `launch` reclaims your run it drives the new
run's app. Name your run on every command. Pass the same `VERIFY_RUN` to take your own run's app with a second `launch` or a
`test-sim.sh` run; otherwise run `stop` or pick another `SIM`.
`stop` refuses the same way when it would act on another run's app, so a
command that lands on the wrong simulator cannot end another agent's drive (issue 660). It can
only refuse what it can tell apart, and that cuts both ways. An unset `VERIFY_RUN` gives it
nothing to compare against, so it steps aside, except that a drive with no `VERIFY_RUN` acts for
the run the last launch on this simulator started, and refuses after that run's launch was
refused. Unless that run was named, a refused `launch` with no `VERIFY_RUN` counts as a refused
launch of that run, so an agent that never names a run cannot drive the app its own refused
relaunch left behind. The refusal prints the way out, which is `stop` and then `launch`. `SIM` has no default, so no command lands on a shared simulator by accident. With
`VERIFY_RUN` set, `tap`, `hold`, `type`, `swipe`, `shot`,
`burst`, and `axe` refuse (exit 75) while another run's app is alive on the simulator, and after a
`launch` of the same run was refused, until a `launch` of it succeeds. So a driver that missed its
own launch's refusal cannot drive or film the app that refusal left behind. Your drive is protected from a
sibling only when the sibling names its own run. Set both on every call whenever another agent
might be on this machine. `launch`, `shot`, and `burst` refuse (exit 75) while a `scripts/test-sim.sh` run holds the
simulator. `test-sim.sh` refuses while a run whose lease is live has its app on it. Each refusal names
the holder and its pid. The lock sees only `scripts/test-sim.sh`, so an XcodeBuildMCP `test_sim` or
a raw `xcodebuild test` on the same UDID is invisible to it. Before a `launch` when another agent
may be testing, run `pgrep -fl "id=<udid>"`. Two CLI drives never collide if each has its own
`WORKOUT_HOME`.

Every claim also waits for the host, up to `WORKOUT_ADMIT_WAIT` seconds (540), while free memory
(`kern.memorystatus_level`, percent) is under `WORKOUT_MEM_FLOOR` (25), and exits 75 with the reason
if it never clears. A claim on a shut-down simulator also waits while `WORKOUT_SIM_CAP` other
simulators are booted (10), and boots it once admitted. At the cap it first shuts down the least
recently used `workout-lane-*` simulator that no run holds, that runs no app but a verify app past
its lease, and that went unclaimed for `WORKOUT_IDLE_MINUTES` (2), and names it on stderr. Each
`build`, each build into the app cache (`install COMMIT`, `launch --at`), and each `test-sim.sh`
build waits for the same floor and takes one of `WORKOUT_BUILD_SLOTS` host-wide build slots (2) the
same way. `build` boots nothing. Admission never reads the load. Run anything else heavy as
`scripts/build-slot.sh <command>` instead of a hand-written `uptime` loop.

## Changing this skill

After an edit to `verify.sh`, `tree.py`, `frames.py`, `scripts/contact-sheet.swift`, or
`scripts/sim-lock.sh`, run `python3 .agents/skills/verify/tests/test_evidence.py`. Also run
`scripts/tests/host-admission.test.sh` after an edit to `verify.sh`, `scripts/sim-lock.sh`, or
`scripts/build-slot.sh`, and `scripts/contact-sheet.test.sh` after an edit to the tiler. CI runs
`test_evidence.py` through `.github/workflows/verify-tools.yml` and every script test through
`.github/workflows/script-tests.yml`.
