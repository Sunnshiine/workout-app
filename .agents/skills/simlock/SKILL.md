---
name: simlock
description: Use before touching an iOS simulator, or before running simctl, xcodebuild for a simulator, XcodeBuildMCP, scripts/test-sim.sh or verify.sh. Simlock shares the Mac's simulators between agents and has rules every agent must follow.
---

Simlock hands out the Mac's iOS simulators so parallel agents do not fight over one or overload the
host. It works only if every agent follows its rules. ADR-0024 records why workout-app uses it.

1. Check it is set up: run `simlock whoami`. If `simlock` is not found, or `whoami` fails, tell the
   user and do not touch any simulator.

2. Get the rules: run `simlock instructions` and follow them. They match the installed Simlock, so
   read them again in each session instead of relying on memory.

3. In this repo, take the simulator through the scripts, which lease it for you:
   - `scripts/test-sim.sh` runs on the lease you hold. Holding none, it leases an iPhone 17 Pro on
     iOS 27.0 and keeps it `WORKOUT_TEST_LEASE_MINUTES` (10) after the run for your next run,
     because Simlock deletes a released device and first-boots a replacement, which loads the
     host for minutes. A run never releases or shortens a lease; `simlock release <id>` does.
   - `verify.sh launch` leases one for your verify run. Later verify calls find and renew it.
     `verify.sh release` gives it back, and Simlock reclaims it after `WORKOUT_LEASE_MINUTES` (60)
     without a call.
   - You hold one lease at a time, and every script uses it. `--sim` and `SIM=` accept only the
     simulator of your own lease.
   - To design on the app, take the lease with `verify.sh launch`. Its 60 min TTL renews with
     every verify call, and a lease test-sim kept becomes one. XcodeBuildMCP calls renew nothing.

4. Never create, boot, shut down, erase, or delete a simulator yourself, and never name one by
   model in a `-destination`. `scripts/lint.sh` fails on each (`scripts/lint-simulators.py`).
   Drive a simulator you leased by its UDID. A raw `xcodebuild` or XcodeBuildMCP call takes no
   lease, so give it the UDID of a lease you hold, never a simulator it picks. For XcodeBuildMCP,
   set that UDID with `session_set_defaults {simulatorId}` alone; `build_run_sim`, `screenshot`,
   `snapshot_ui` and `touch` read it from there, and a hook refuses any other.

More: https://callstackincubator.github.io/simlock/docs/getting-started/connect-your-agent/
