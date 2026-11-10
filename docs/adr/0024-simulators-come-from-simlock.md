# Simulators come from Simlock

Agents for several apps share one Mac. workout-app gave its agents simulators through its own pool: a
`workout-lane-<name>` clone per lane (`scripts/sim-pool.sh`), a host cap of `WORKOUT_SIM_CAP` (10)
booted simulators with idle-lane reclaim (ADR-0020), and a slim boot list (ADR-0022). jenns-app, on
the same Mac, takes its simulators from Simlock, a daemon that leases simulators to agents. Neither
scheme saw the other's simulators, so the two caps added up. During a four-PR run on 2026-11-09 the
1-minute load sat between 386 and about 1000 for hours, a CRAP gate run failed, and builds died at
tool time limits. The operator asked to move workout-app onto Simlock too.

What Simlock 0.6.0 on this host limits, read from `simlock config` and `simlock status` on
2026-11-10:

- At most 6 running iOS simulators host-wide (`capacity.config.limits.ios.maxRunning`), within a RAM
  budget of 1.5 GiB per iOS device out of 28 GiB. A request past the cap waits in Simlock's queue.
- One lease per agent identity (`lease.maxPerRequester`). Under Claude Code the identity is the
  session, `claude-code:<CLAUDE_CODE_SESSION_ID>`. A second request fails with exit 13.
- A warm pool keeps learned device kinds booted, so a lease of a warm kind takes about a second.
  Releasing a lease resets the device. UDIDs are reused across agents.
- A lease taken with `--bind-pid` ends when that process dies, even by SIGKILL. A detached lease ends
  at its TTL unless renewed.
- The grant's `environment` is empty here, so the simulator is in Xcode's own device set and
  `xcodebuild -destination id=<udid>` and `xcrun simctl` reach it by UDID.

What it does not limit: compiles. `xcodebuild`, `swift build` and `swift test` take no lease.
ADR-0020 measured one build alone taking the load from 7 to 281. So the overnight load most likely
came from builds, and Simlock does not cap them. This ADR moves the simulators; it does not claim to
fix that load.

## Decision

- **Every simulator a script or skill reaches comes from a Simlock lease.** `claim_sim` in
  `scripts/sim-lock.sh` takes a lease bound to the script's pid for `scripts/test-sim.sh`, and
  `hold_lease` takes a detached lease, `WORKOUT_LEASE_MINUTES` (60) long and renewed by each call,
  for `verify.sh`. Both lease an iPhone 17 Pro on iOS 27.0, the Visual Baseline device. `--sim` and
  `SIM=` name only the caller's own lease.
- **Simlock's caps replace workout-app's simulator gates.** `WORKOUT_SIM_CAP`, idle-lane reclaim
  (`WORKOUT_IDLE_MINUTES`, `WORKOUT_SLEEP_MINUTES`), `scripts/sim-pool.sh`,
  `scripts/measure-host.sh`, and the lane simulator go. A lane is now a worktree and an evidence
  directory.
- **Build slots and the memory and disk floors stay** (ADR-0020). They are the only gates on
  compiles, and Simlock has none.
- **Leases are full boots**, Simlock's default and the kind its warm pool keeps ready. Simlock's
  slim mode turns off chronod and liveactivitiesd, which `features/live-activity.md` drives, so
  ADR-0022's lane list no longer applies on this Mac. CI keeps its own slim boot.
- **CI keeps its own simulator.** A GitHub runner is single-tenant and has no Simlock, so
  `scripts/ci/` creates and boots one there. `scripts/test-sim.sh` and `verify.sh` exit 78 without
  Simlock.
- **A lint keeps it so.** `scripts/lint-simulators.py`, run by `scripts/lint.sh`, fails on a
  simulator created, booted, shut down, erased, deleted or cloned outside `simlock simctl`, on a
  destination that names a simulator by model, and on `xcodebuild test` outside `test-sim.sh`, under
  `scripts/` and `.agents/skills/`. Each exception names its reason in the script.

## Considered alternatives

- *Keep the pool and add Simlock beside it.* Two pools on one Mac is the problem this fixes.
- *Lease from `scripts/lane.sh up` and keep the simulator for the lane's life.* One lease per agent
  and a lane per agent would hold six seats for idle lanes, the waste ADR-0020 reclaimed.
- *Lease slim for `test-sim.sh` and full for verify.* Two kinds split the warm pool, and a UI test
  that needs a disabled job would fail only here. Measure it before adopting it.

## Consequences

- Six simulators, not ten, run at once across every app on the Mac. A seventh agent waits in
  Simlock's queue up to `WORKOUT_ADMIT_WAIT` (540 s), then `test-sim.sh` exits 75.
- An agent that holds a verify lease runs `test-sim.sh --sim <udid>`, because its second request is
  refused. In-process subagents that share their parent's session share its one lease.
- A raw `xcodebuild` or XcodeBuildMCP call takes no lease. The lint cannot see an agent's tool calls.
  The XcodeBuildMCP tools that boot or pick a simulator should be denied in `.claude/settings.json`,
  as jenns-app does.
- Worktrees on older commits keep their own `sim-pool.sh` and its `workout-lane-*` simulators until
  they rebase. Nothing here deletes those simulators. Prune them by hand once no lane uses them.
- The overnight load needs its own fix, on builds. A host-wide build gate across apps is the next
  thing to measure.

Supersedes ADR-0020's simulator cap and idle-lane reclaim, and ADR-0022 for lanes on this Mac.
