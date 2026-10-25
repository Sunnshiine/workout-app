# Lane simulators boot without the jobs no test uses

ADR-0020 found that CPU limits how many lanes the Mac runs at once, and that an idle simulator is not
free. A lane boots often. At the cap, an idle lane's seat is reclaimed after `WORKOUT_IDLE_MINUTES`
(2), and under it any boot shuts down a lane unused for `WORKOUT_SLEEP_MINUTES` (30). The lane's
next run boots it again, so a busy day boots lanes dozens of times. Every boot paid the same price,
because a settled template does not help. A second boot of one clone cost as much as its first.

We measured on 2026-10-19, on the ADR-0020 host (Apple M6, 12 cores, macOS 27.0.1, Xcode 27.0, iOS
27.0), with three or four other simulators booted and a 1-minute load of 2.4 to 26. One reading
was 147, at the start of the first stock boot, and that boot's CPU fell inside the stock range.
Each boot was a fresh `simctl clone` of `workout-template-v1`, booted with plain `simctl boot`, in
five alternating pairs (stock, slim, slim, stock, and so on). The slim side's disable list came
from `sim-pool.sh`'s own `disable_jobs`. The CPU count is exact. It is the `proc_pid_rusage` own and reaped
children CPU of every process in the device's `launchd_sim` tree, over a fixed 600 s window from
`simctl boot`. The footprint is the summed `phys_footprint` of that tree at 600 s. The last column
is the CPU from 300 s to 600 s after boot. For stock it is close to the idle rate, since an idle
stock simulator measured 0.12 core over an hour. No idle slim simulator was measured that long.

| Boot | Boots | CPU s in 600 s, median (range) | Live processes at 600 s | Memory footprint at 600 s | Cores from 300 to 600 s |
|---|---|---|---|---|---|
| stock | 5 | 564 (544 to 579) | 325 (324 to 328) | 2.9 GB (2.7 to 3.0) | 0.106 (0.087 to 0.128) |
| slim | 5 | 172 (163 to 187) | 157 (156 to 159) | 1.2 GB (1.22 to 1.24) | 0.010 (0.009 to 0.018) |

A slim boot costs about 30% of a stock one, and holds 40% of its memory. Over 90% of either boot's
CPU is spent in its first 300 s. Every boot on each side landed within 9% of its median, so the
slim side is not bimodal. An earlier reading of 75 CPU s came from sampling `ps` every 2 s, which
misses short-lived processes and read stock boots at about half their exact cost too.

Where a stock boot's CPU goes: about 410 processes start in its first 600 s, and most cost one
or two CPU seconds each. About 18 wallpaper poster extensions take a quarter of it, about 30 widget extensions take a
fifth, and the rest is spread over Siri, Spotlight, iCloud, Photos, Health, Mail, and the other
daemons of a phone nobody is using.

## Decision

- **`sim-pool.sh create` writes a launchd disable list into every lane.** `launchd_sim` reads a
  device's disable list from `/private/var/tmp/com.apple.CoreSimulator.SimDevice.<UDID>/disabled.plist`,
  a host file, each time it boots. `simctl clone` does not copy it, so the template cannot carry
  it. Because the file is read at boot, every route to a boot gets the slim boot: `test-sim.sh`,
  `verify.sh`, `sim-pool.sh boot`, XcodeBuildMCP, and a raw `xcodebuild`. `create` writes it for a
  new lane and for a lane that already exists, which takes effect at its next boot.
- **The list is data, `scripts/sim-pool-disabled-jobs.txt`.** It holds 155 job labels in groups,
  each with the feature it turns off. A label goes on it when it is a job in the iOS runtime and
  the app, its tests, and the verify skill do not use it.
- **`pairedsyncd` is not on the list.** CoreSimulator writes explicit enables for the Watch
  pairing jobs, `com.apple.pairedsyncd` among them, into `disabled.plist` at every boot, over any
  entry the list wrote. It ran once and exited on each of the ten boots, stock and slim.
  `managedappdistributiond` is on the list, because on each stock boot it ran 54 to 57 times
  in 600 s.
- **What stays on.** SpringBoard, backboardd, runningboardd, installd, the keyboard and
  accessibility jobs, logd and diagnosticd, mobileassetd, linkd, and swcd. chronod and
  liveactivitiesd stay on, because `features/live-activity.md` drives the app's Live Activity,
  which chronod renders. navd stays on, because chronod's stock Maps widget spins without it.

## What a lane loses

Changing the wallpaper (the Home Screen still draws its default one), Spotlight and Settings search, push, StoreKit, iCloud and
the Apple Account, Photos analysis, Siri and dictation's server side, Health, and the stock apps'
sync. A live Google sign-in through the web sheet is untested on a slim lane. Lanes run on
fixtures, so no lane needs one. For a stock boot, delete the lane's `disabled.plist` while it is
Shutdown. The next `create` writes it again.

## Considered alternatives

- *`simctl boot --disabledJob=<label>`.* It covers only boots that `sim-pool.sh` or `sim-lock.sh`
  make. XcodeBuildMCP and a raw `xcodebuild` boot without it.
- *Disable chronod too.* That stops all 30 widget extensions, but it also stops the app's Live
  Activity, which verify drives.
- *Set the stock widget extensions to ignored with `pluginkit -e ignore` in the template.* One
  probe, on a template that had already booted once, settled at 80 CPU s against 144 for this list
  alone, both read by sampling `ps`. pluginkit's choice lives in the device's data, so the template would carry it, but that
  is a new template recipe. Building it deletes `workout-template-v1` while worktrees on older
  commits still clone it. It is the next step to measure.

## Consequences

- `scripts/measure-host.sh` clones through `sim-pool.sh create`, so its rows now measure slim
  lanes. ADR-0020's table was taken on stock ones.
- A test that needs a disabled job fails only on a lane. Take the job off the list, or boot that
  lane stock as above.

<!-- doc-symbols: not-in-tree disabled.plist -->
