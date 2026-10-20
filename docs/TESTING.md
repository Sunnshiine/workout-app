# Testing

## Change Risk Gate

`scripts/crap.sh gate` runs in the `swift-tests` CI job. CI passes `--xcodebuild`, which runs the same
package tests through xcodebuild's compilation cache instead of `swift test --enable-code-coverage`. It
scores every production function in the headless scope with CRAP (`cc^2 * (1 - coverage)^3 + cc`),
and fails when a function not in `tools/crap/baseline.tsv` scores above 6, when a baselined function
scores above its recorded value, when a baseline row no longer applies, or when a row gives no reason.
After lowering a score, run `scripts/crap.sh baseline` and commit the smaller baseline. A new function
that stays above 6 needs a row from `scripts/crap.sh baseline` with a written reason, or the gate keeps
failing. ADR-0016 records the decision; the counting rules and their tests live in `tools/crap/`.

Coverage counts only lines `swift test` executes. A test that covers a function through the interface
its callers use is the intended way to lower a score; a test that calls internals to paint lines green
is not, and neither is a split that produces functions without a name a reader would look for.

## Flaky Tests

A test passes every time or it is a defect. `scripts/flake-hunt.sh [--repetitions N] [FILTER]` repeats
`swift test` until a failure while busy loops hold every core, which surfaces a timing race within a few
hundred repetitions. Run it on any test that awaits concurrent work before you commit that test.

CI runs a narrower hunt on every pull request. After the gate, `scripts/flake-guard.sh` repeats each test
whose lines the pull request changed, up to 20 times, on the products the gate built, while three busy
loops per core hold the CPU. It stops at the first failure or after 300 seconds. A test's lines run from
its `@Test` to the brace that closes it, so the guard repeats only the tests the diff touched and does
not go red on a flake the pull request did not add. Deleting a test selects nothing. A moved test counts
as new. A failure names the test, the repetition, its declaration, its first issues, and the
`flake-hunt.sh` line that reproduces it. A pull request that changes no test runs nothing. A change to
`Tests/Support/`, or to a helper or attribute outside every test, selects nothing and prints a note, so
hunt the tests that use it yourself. `scripts/changed-tests.sh` prints the selection.

Two shapes caused every flake found so far, and neither survives the hunt:

- A fixed number of `Task.yield()` calls before asserting on work another task does. The runtime does not
  promise that ordering. Have the fake resume the test after the work runs, as
  `ManualSessionTransitionClock.advance()` does.
- A wall-clock budget, such as polling for 10 seconds. Under load the budget runs out, the test returns,
  and a task it started keeps running against torn-down state. Await the event or the task instead.

A wait for work the test does not control is bounded, or a regression that skips the work hangs the run
instead of failing it. A continuation ignores the time limit's cancellation, so a fake never parks the
test on one. It polls state on the main actor, where the work that sets it runs, and records a failure
when the poll runs out: `waitUntil` and `HeldCall.waitUntilHeld` in `Tests/Support/` are the shapes to
copy, as `ManualSessionTransitionClock.waitForSleep()` does (#746).

## Parallel Agents

Each concurrent simulator run takes its own worktree and simulator. `scripts/lane.sh up` makes
both, cloning the simulator through `scripts/sim-pool.sh` (Running beside other agents, below).
`scripts/test-sim.sh` and `verify.sh launch` share the lock in `scripts/sim-lock.sh`, which exits 75
while another run holds that simulator. The same script admits a run only while the host has room:
it waits while free memory (`kern.memorystatus_level`) is under `WORKOUT_MEM_FLOOR` percent, before
a boot while `WORKOUT_SIM_CAP` other simulators are booted and no lane simulator is idle, and
before a build while every `WORKOUT_BUILD_SLOTS` slot is taken, then exits 75 after
`WORKOUT_ADMIT_WAIT` seconds, restarted each time a build slot changes hands. It does not read the
load, which one build drives past 250 (ADR-0020). `scripts/build-slot.sh` runs anything else heavy
under a build slot, as in `scripts/build-slot.sh swift test`. Before trusting `WORKOUT_SIM_CAP` on
a new Mac or Xcode, run `scripts/measure-host.sh 10 unit` and compare its line with ADR-0020. A
timing or motion measurement taken under load still describes the host, not the app, so record the
1-minute load beside it
(`test-sim.sh` prints `load1=`) and rerun when it is high. `verify.sh launch` and most UI tests
turn animations off, so they miss a defect that exists only in motion. The verify `SKILL.md` films
motion with `verify.sh launch --animated` and `verify.sh record`. Its
`.agents/skills/verify/motion/cardframe.py` measures a take, and `cardstill.py` beside it films and
judges a set of takes against a control commit. A UI test that needs motion launches with
`animated: true`.

`scripts/dev-usage.sh` meters what each agent, simulator, and build costs the host. The numbers are
exact: they come from `proc_pid_rusage`, which adds a reaped child's CPU to its parent, so a
compiler that ran for a second between two samples still counts. Never measure CPU with `ps`,
which misses those. `scripts/dev-usage.sh install` loads a user LaunchAgent that runs
`scripts/dev-usage.sh sample` every 60 s, and `uninstall` removes it; no other script installs it.
The agent runs a copy of the scripts kept in the ledger, so rerun `install` after pulling a change
to them.
The ledger is in `~/Library/Logs/WorkoutTracker/dev-usage/` (`WORKOUT_DEV_USAGE_DIR`). Each sample
appends one row per agent, keyed by the worktree holding its cwd, one per booted simulator, keyed
by device name, and one for the host. `scripts/dev-usage.sh report --since 2h` prints each one's
CPU seconds (`cpu_s`), those seconds per second of the window (`cores`), its part of the host's
busy CPU (`share`), and its peak memory footprint (`peak_mb`). The `rest` row is host CPU outside every
agent and simulator. `scripts/build-slot.sh` runs its command under `scripts/dev-usage.sh record`,
which appends one row per run, and `report --by command` gives each command's count, median and p90
CPU seconds, and peak RSS. An in-process subagent counts toward its parent's worktree, since it
shares the parent's process.

## AI-Generated Code Gate

The acceptance gate prioritizes behavior correctness first. Simulator user-flow tests protect the
small number of workflows where app wiring matters. Visual Regression tests protect known-good
pixels for covered surfaces.

Layer duties:

- `swift test` proves domain and module behavior through public interfaces with realistic inputs.
- Component tests prove SwiftUI component state contracts at unit-test speed, without rendering
  pixels.
- `scripts/test-sim.sh unit` proves the app target compiles and simulator-hosted tests run.
- Visual Regression tests prove rendered screens match committed Visual Baselines.
- UI tests prove critical user flows through real controls.

Component tests are not full app launches. They do not touch Google auth, the network, or complete
navigation flows. They cover view-facing labels, accessibility strings, enabled states, form state,
and progression state. Visual Regression tests are the separate pixel layer; do not use component
tests to assert screenshots.

`Tests/Component/ContrastTests.swift` classifies every palette and lighting colour role and checks
each ink where views draw it, worst case over the page: 4.5:1 text, 3:1 rims and glyphs. It parks
a pair failing now with a floor and lists the quiet roles it never measures. It cannot see a
call-site opacity, or the palette's computed aliases such as `accent`: those are measured only
through the stored role each returns. `system_ink_outside_the_palette`
flags system .secondary to .quinary and *Label inks in `App/`; exempt a line with a reason on it.

Visual vocabulary:

- **Visual Regression test**: a hosted unit test under `Tests/Visual` that renders a deterministic
  SwiftUI view and compares it to a committed reference image.
- **Visual Baseline**: the committed PNG under `Tests/Visual/__Snapshots__` that defines the
  known-good pixels for one Visual Regression test.

Visual tests use `swift-snapshot-testing` as a test-only dependency. Recording is disabled by
default, so a missing or changed Visual Baseline fails instead of silently re-recording. New or
intentional baseline changes must be recorded deliberately.
The shared Visual trait configuration is pinned to iPhone 17 Pro on the iOS 27.0 runtime (the
CI runner's preinstalled runtime — the pin moves with the runner image, see ADR-0007), light
mode, `en_US`, and fixed default Dynamic Type.

Precision is the fraction of pixels that must match. `WorkoutVisualBaseline.precision` is exact
(`1.0`). A test compares at `0.999` when its assertion resolves to
`WorkoutVisualBaseline.labelAntialiasingPrecision`, passed directly or through its suite's
snapshot helper, so up to 0.1% of the image may differ and the test still passes.
`grep -rn 'precision' Tests/Visual` shows each helper's precision and every test that passes its
own. That budget absorbs text anti-aliasing, and it also hid a whole missing Settings row from the
Block grid baselines. For a change to one of those surfaces, open the rendered image and compare it
with the baseline yourself; a green run does not prove they match.

Recording recipe (issue #471): the recording switch is the suite trait, not an environment
variable — `SNAPSHOT_TESTING_RECORD` is overridden by the explicit trait and does nothing here.
To record: flip the affected suite's `@Suite(.snapshots(record: .never))` to
`.snapshots(record: .all)` in `Tests/Visual/*.swift`, run the Visual suite on the pinned
simulator (`scripts/test-sim.sh --sim "$(scripts/ensure-simulator.sh 'iPhone 17 Pro' 27.0)" visual`), then
revert the trait to `.never` before committing. Two caveats: a record run that crashes leaves
the stale PNG silently in place, and the CI runner is the canonical recorder — baselines
recorded on other machines differ at exact precision (issue #479). To take the runner's render,
push without recording, then run `scripts/ci-visual-diffs.sh <PR>` to list each failing snapshot
with its runner and difference images, and `scripts/ci-visual-diffs.sh <PR> --apply <test>...` to
copy the runner's render over those baselines, or create a new one. Commit the result; the next
`visual-tests` run is the proof.

Target directory structure:

- `Tests/Unit`: domain, parser, store, persistence, sync, and write-path tests. Runs in the
  existing fast `WorkoutTrackerTests` target.
- `Tests/Component`: SwiftUI component state-contract tests that still run at unit-test speed.
  Runs in the existing fast `WorkoutTrackerTests` target.
- `Tests/Visual`: hosted Visual Regression tests plus Visual Baselines. Runs in the
  `WorkoutTrackerSnapshotTests` target via xcodebuild, not `swift test`. It also holds hosted
  layout tests, which put an `App/` view in a real window and assert its geometry with no image.
  `Package.swift` excludes all of `Tests/Visual` from `swift test`, so a test here can use `App/`
  views without the per-file exclude a `Tests/Unit` file needs.
- `Tests/UI`: simulator XCUITest coverage that launches the app and drives real controls.
  Uses a separate Xcode UI-test target, split by purpose into UI Integration Smoke and the
  UI Interaction Suite.

Test doubles policy:

- `Tests/Unit` may use pure fixtures and protocol stubs at true I/O boundaries only: Sheets client,
  auth/defaults, and SwiftData in-memory containers.
- `Tests/Component` may use deterministic domain objects and presentation-state builders. It should
  assert component state contracts, not fake complete app flows.
- `Tests/UI` launches the real app with deterministic fixture mode, fakes external services at
  launch boundaries, and drives real controls through accessibility.
- Automated tests must not hit live Google auth, live Google Sheets, or real network connectivity.

The UI XCUITest boundary, UI-test frame assertions, and the representative UI Integration Smoke
scope live in [docs/testing/ui-tests.md](testing/ui-tests.md). Read it before you add, delete, or
narrow a UI test, or change a frame or layout assertion in one.

Smoke selector command:

```bash
scripts/test-sim.sh \
  WorkoutTrackerUITests/WorkoutTrackerUISmokeTests \
  WorkoutTrackerUITests/PartiallyUploadedBlockUISmokeTests
```

The whole UI target, smoke included:

```bash
scripts/test-sim.sh ui
```

Reading a `scripts/test-sim.sh` run:

- A selection that includes `WorkoutTrackerUITests` first runs `scripts/sim-keyboard.sh ensure`.
  It sets `AutomaticMinimizationEnabled` in the simulator's `com.apple.keyboard.preferences` to 0
  when it reads 1, the state that hides the software keyboard below the window (#700). An AXe key
  or type event into a focused field sets it back to 1, so a verify session can leave it wrong.
- The last line is `test-sim: suite=<s> passed=<n> failed=<m> expected=<k> exit=<e>
  load1=<start>/<end> bundle=<path>`. `expected=` counts tests whose only issues were known
  issues, which `passed=` leaves out. `exit=` is the script's status, which a pipe such as `| tee`
  hides.
- A run's files in `.build/test-sim` are `<stamp>-build.log`, `<stamp>-test.log`,
  `<stamp>.xcresult`, and `<stamp>-diffs`, and its test log ends with its result line. Each run
  keeps the five runs written last. It deletes an older run's files when that run's test log ends
  with a result line and none of its files changed in the last 30 minutes, so a run still in
  progress in the same checkout keeps its log and bundle. A run with no result line whose files
  have not changed for 24 hours was killed (SIGKILL, power loss) and is deleted too. Copy a bundle
  or diff you cite into your proof directory, because only five runs are kept.
- After a failed visual run, `scripts/snapshot-diffs.sh <bundle>` exports the reference, failure,
  and difference images and prints their paths.

Running beside other agents (`scripts/lane.sh --help` and `scripts/sim-pool.sh --help` hold the details):

- `scripts/lane.sh up <name> <commit>` makes a lane: a detached worktree at that commit under
  `.claude/worktrees/<name>` with `Secrets.xcconfig` in place, and its own simulator, cloned from a
  template `scripts/sim-pool.sh` builds on first use. It prints three `export` lines: `SIM`,
  `LANE_WORKTREE`, and `VERIFY_EVIDENCE`, an evidence directory in the main checkout that outlives
  the worktree. The shell forgets them between calls, so start each call with
  `env=$(scripts/lane.sh env <name>) && eval "$env" && ...`.
- The lane's simulator stays Shutdown until something boots it. `scripts/test-sim.sh` and
  `verify.sh` boot it themselves. Before a raw `xcodebuild` or XcodeBuildMCP call on a lane, run
  `scripts/sim-pool.sh boot <name>`. All three boot through the same host admission, which waits
  while free memory is under `WORKOUT_MEM_FLOOR` or `WORKOUT_SIM_CAP` other simulators are booted.
  At the cap it first shuts down the least recently used lane simulator that no run holds, that
  runs no app, and that nobody claimed or booted through `sim-pool.sh boot` for
  `WORKOUT_IDLE_MINUTES` (2). Under the cap, every boot shuts down one such lane unused for
  `WORKOUT_SLEEP_MINUTES` (30; 0 turns it off): an idle lane simulator uses about 0.12 core, so in
  half an hour it burns more CPU than its next boot. Its next run boots it again. Stop an app you launched through
  XcodeBuildMCP when you are done, or its lane never counts as idle.
- `scripts/lane.sh down <name>` deletes the lane's simulator first, refusing with exit 75 before it
  touches anything else while a run holds the simulator. It then saves any uncommitted or staged
  diff, untracked files, commits no branch holds, and the lane's results under `.build` (`test-sim`,
  `verify`, `crap`, `flake-hunt`, `mutate`, `check-each-commit`) into that evidence directory, and
  removes the worktree and its DerivedData.
- `scripts/prune-merged-worktrees.sh` lists a clean lane idle for `--lane-idle-days` (default 3)
  as a candidate, and `--apply` removes it through `lane.sh down`.

Shared fixture policy:

- Put shared builders and named scenarios under `Tests/Support`.
- Reuse the same canonical scenarios across layers, with layer-specific assertions.
- Initial scenarios: fresh configured app, Current Session with Pending Sets, partially Logged
  Session, Open Exercises, sync failure, queued write, and Block Overview with mixed Session states.
- UI launch fixtures should stay small and named. Add a new UI fixture route only when it protects a
  distinct app-layer wiring risk that cannot be reached from the existing shared scenarios without
  making the test substantially broader.

Per-change test selection:

- Parser, write-path, progression, persistence, and store changes require unit tests.
- View-facing labels, enabled states, accessibility text, and active-card state changes require
  component tests.
- Known visual surface changes require the relevant Visual Regression tests to pass with recording
  disabled.
- Navigation, launch state, real control interaction, and cross-store workflows require UI
  integration tests.
- Pure visual restyling requires relevant Visual Regression coverage when the surface has a
  baseline. Component or UI tests are required only when behavior or state contracts change.

Agent gate policy:

- While you work, run the narrowest tests for the layer you change.
- Before a PR is ready, run every layer the per-change selection above names, plus `swift test`
  and `scripts/lint.sh`. A change to navigation or real controls also runs the smoke selector, and
  one to keyboard focus, gestures, or scrolling runs `scripts/test-sim.sh ui`.

# Manual Testing on the iOS Simulator

Running the app from Xcode, first-run onboarding, and resetting state live in
[docs/testing/manual-simulator.md](testing/manual-simulator.md).
