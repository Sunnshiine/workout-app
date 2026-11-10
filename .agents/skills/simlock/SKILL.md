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
   - `scripts/test-sim.sh` leases an iPhone 17 Pro on iOS 27.0 for one run and releases it when the
     run ends, even when the run is killed.
   - `verify.sh launch` leases one for your verify run. Later verify calls find and renew it.
     `verify.sh release` gives it back, and Simlock reclaims it after `WORKOUT_LEASE_MINUTES` (60)
     without a call.
   - You hold one lease at a time. A second request fails, and `test-sim.sh` exits 75 naming the
     simulator you hold. Pass that one: `scripts/test-sim.sh --sim <udid> unit`. `--sim` and `SIM=`
     accept only the simulator of your own lease.

4. Never create, boot, shut down, erase, or delete a simulator yourself, and never name one by
   model in a `-destination`. `scripts/lint.sh` fails on each (`scripts/lint-simulators.py`).
   Drive a simulator you leased by its UDID. A raw `xcodebuild` or XcodeBuildMCP call takes no
   lease, so give it the UDID of a lease you hold, never a simulator it picks. XcodeBuildMCP's
   `build_run_sim`, `screenshot` and `tap` take that UDID as `simulatorId`; a hook refuses any other.

More: https://callstackincubator.github.io/simlock/docs/getting-started/connect-your-agent/
