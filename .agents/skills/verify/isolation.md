# Isolation

Read `SKILL.md` first. This file is the reference for what each command refuses, and why, when several
runs or agents share a simulator or the host.

`launch`, `install`, and `scripts/test-sim.sh`
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
build waits for the same floor and for `WORKOUT_DISK_FLOOR` MB of free disk (4096), and takes one
of `WORKOUT_BUILD_SLOTS` host-wide build slots (2) the same way. `build` boots nothing. Admission
never reads the load. Run anything else heavy as `scripts/build-slot.sh <command>` instead of a
hand-written `uptime` loop.
