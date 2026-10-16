# Measured host admission for parallel simulator runs

Agents in parallel lanes share one Mac. `scripts/sim-lock.sh` admits each `test-sim.sh` run, `verify.sh`
claim, and pool boot onto it through three gates: the 1-minute load under `WORKOUT_LOAD_LIMIT` (50), at
most `WORKOUT_SIM_CAP` (6) booted simulators, and `WORKOUT_BUILD_SLOTS` (2) concurrent builds. Nobody
measured any of the three numbers. Agents still lost long stretches waiting at admission. Nothing shut a
lane's simulator down until the lane was removed, so booted simulators piled up.

We measured the host on 2026-10-15: a Mac mini with an Apple M6, 12 cores, and 32 GB, on macOS 27.0.1
and Xcode 27.0. Each trial booted N pool clones and ran N `test-sim.sh` runs at once with the gates
lifted. Every two seconds it sampled the load, CPU, free memory (`kern.memorystatus_level`), and swap.
Each trial ran once unless a row says otherwise. The last two rows ran on 2026-10-16 on the gates
this ADR chose, in 12 fresh lanes, two more than the cap. Both times booted simulators peaked at 10,
two waiting runs each reclaimed an idle lane, and swap did not grow.

| Trial | N | Slowest run | Runs with a failure | Lowest free memory |
|---|---|---|---|---|
| unit + visual + UI smoke, prebuilt | 1 | 64 s | 0 | 78% |
| | 4 | 125 s | 0 | 66% |
| | 8 | 179 s | 0 | 54% |
| | 10 | 236 s | 0 | 47% |
| | 12 | 256 s | 0 | 42% |
| full UI suite, prebuilt, two trials each | 4 | 285 s | 2 of 8 | 75% |
| | 6 | 363 s | 1 of 12 | 64% |
| | 8 | 476 s | 4 of 14 | 57% |
| one UI test alone, five trials | 1 | 19 s | 0 of 5 | 80% |
| cold build + unit, one lane each | 1 | 73 s | 0 | 76% |
| | 6 | 268 s | 0 | 49% |
| | 6, 2 build slots | 230 s | 0 | 69% |
| | 6, all three gates | 550 s | 0 | 64% |
| warm build + unit, all three gates | 6 | 359 s | 0 | 71% |
| cold build, mixed unit, visual and UI smoke, this ADR's gates | 12 | 669 s | 1 (#899) and two exit 75 | 59% |
| | 12, after the build-queue fix | 769 s | 0 | 50% |

What the numbers say:

- **CPU limits throughput. No host limit appeared up to 12 simulators.** CPU saturated from N = 2.
  Prebuilt runs per minute rose from 0.94 at N = 1 to 2.68 at N = 8 and 2.81 at N = 12. Over the same
  range each run took 3.6 times as long. Swap stayed at zero.
- **The UI failures are one load-sensitive test, not a break point.** Six of the seven failing runs failed
  `testTerminalMoveOnReturnsToAccessibleBlockGrid` (#907). The rate did not climb steadily with N: 2 of 8
  runs at 4, 1 of 12 at 6, 4 of 14 at 8. The test
  passed five times out of five alone.
- **The 1-minute load is not a health signal on this host.** One build alone takes it from 7 to 281.
  Every trial past N = 2 ran at a load of 350 to 1000. A gate at 50 admits a run only while nothing else
  runs. With six warm lanes it held the last two for 317 s while the host averaged 58% CPU. Those two
  finished at 359 s, while the first two took 39 s. With six cold lanes, the last two waited 458 of
  their 540 s budget. This is the hang the lanes saw.
- **Build slots earn their place.** Six cold lanes behind 2 slots finished sooner, at 230 s against 268
  s. They also used 20 points less memory than six unbounded builds.
- **An idle simulator is not free.** Eight freshly booted, idle clones held the CPU at 100% for the two
  minutes the trial lasted. Six lane simulators left booted after one trial raised the next trials to
  14 booted devices.
- **Memory is what grows with load.** Each running simulator took about 1 GB and each cold lane about
  1.7 GB, build and simulator together.

## Decision

- **Admission stops reading the load.** `WORKOUT_LOAD_LIMIT` keeps one job, in `verify.sh record`. There
  it judges whether a motion take measured the app or the host.
- **A memory floor is the safety gate.** A claim, a boot, or a build waits while
  `kern.memorystatus_level` is under `WORKOUT_MEM_FLOOR` (25). Exhausted memory is what kills simulator
  processes. No trial came near 25, so the floor guards a smaller host or a heavier mix and costs
  nothing here.
- **`WORKOUT_SIM_CAP` rises from 6 to 10.** That is the agent count lanes are meant for. Ten measured
  clean, and throughput is flat from 8 to 12.
- **An idle lane simulator gives its seat back.** When a boot would pass the cap, admission shuts down
  the least recently used booted `workout-lane-*` simulator that meets all of these:
  - no run holds it
  - no app runs on it, except a verify app past its lease (an app's extensions, such as the widget,
    do not count)
  - its lock has gone untouched for `WORKOUT_IDLE_MINUTES` (2) since its last run ended

  Its next run boots it again in seconds. Admission never shuts down a device without the
  `workout-lane-` prefix. `sim-pool.sh boot` starts the idle clock too.
- **`WORKOUT_BUILD_SLOTS` stays at 2.** `scripts/build-slot.sh <command>` lets `swift test` and other
  heavy commands take a slot. It replaces `scripts/wait-load.sh`, which waited on the load.
- **A moving build queue is not a stuck one.** A wait for a build slot restarts its
  `WORKOUT_ADMIT_WAIT` budget each time a slot changes hands. Exit 75 means one holder kept a slot for
  the whole budget. A claim also waits for a free slot before it reclaims a seat, so it never shuts
  down a lane for a seat it cannot use yet.
- **`lane.sh down` ignores Xcode's orphaned helpers.** A build leaves `ibtoold`, and a booted
  simulator leaves `DTServiceHub`, working in the lane's worktree for minutes after the run. Both
  have launchd for a parent. `down` used to refuse those lanes as in use. A process with a live
  parent still holds the lane, even when it is an Xcode tool.

## Considered alternatives

- *Keep the load gate and raise the limit.* One build reaches 281. Any limit that admits two builds
  admits everything, so the gate stops gating.
- *A separate, smaller cap for UI suites.* UI failures were flat from 4 to 8 and came from one test.
  A second gate would slow every UI run to hide one test.
- *Share one booted simulator and run on it serially.* Throughput at 8 was 2.8 times throughput at 1, so
  running serially gives most of the host away.
- *Shut a simulator down at the end of every run.* An agent reruns tests minutes later, and each boot
  costs seconds plus a CPU spike. Reclaiming at the cap pays for a boot only when a seat is short.
- *Move more work to the headless `workout` CLI (ADR-0015).* It is still the cheapest place for store
  and sync behavior, and it needs no admission. It does not compile the app or run the UI suites, and
  those are what these gates are for.

## Consequences

- Another host should measure before it trusts these numbers. The harness for this study was a
  throwaway script outside the repo. Committing a rerunnable version is a follow-up.
- A test with a wall-clock window sees runs take up to 3.6 times as long at 10 simulators. A test that
  fails only under load gets triaged with `scripts/flake-hunt.sh`, as #907 is. A failing test is not a
  reason to lower the cap.
- A raw `xcodebuild` or XcodeBuildMCP call takes no lock. If such a call starts more than
  `WORKOUT_IDLE_MINUTES` after the lane's last run or `sim-pool.sh boot`, and before the app launches,
  it can lose its simulator to a reclaim. Run `sim-pool.sh boot <lane>` right before such a call.
- Worktrees on an older commit keep enforcing the old gates through their own copy of `sim-lock.sh`.
  This lasts until they rebase.
- This ADR does not cover telling a CoreSimulator fault from a test failure (#908).
