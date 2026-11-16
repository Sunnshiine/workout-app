# Leases are slim by default

ADR-0024 made every Simlock lease a full boot. Simlock's slim mode then turned off chronod and
liveactivitiesd, which `features/live-activity.md` drives, and the ADR set aside a slim lease for
`test-sim.sh` until it was measured. A probe has measured it since, and the operator has made slim
the host's default.

What probe SLIM-1 measured on 2026-11-15, on Simlock 0.6.0, with every slim group turned off:

- A slim iPhone 17 Pro on iOS 27.0 ran far fewer processes than the full devices in the same window,
  and idled near zero CPU. The counts depend on Simlock's slim config, so this ADR does not pin them.
- On slim, `verify.sh build`, `launch`, `shot` and `tap` saw and drove the app. So did XcodeBuildMCP's
  `build_run_sim`, `snapshot_ui`, `touch` and `screenshot`. The Google sign-in sheet opened and
  loaded.
- The Live Activity did not appear on slim, in the Dynamic Island or on the Lock Screen. ActivityKit
  could not reach its service. The same drive passed on a full lease.
- Every slim lease was a cold boot of 21 to 47 s. A warm full lease took 0.6 to 5 s, because the
  warm pool held full devices.

Since 2026-11-16 the host's Simlock serves slim when a lease names no mode. On that day its slim
config turned off the siri, search, store, pim, web, family, health, photos, apps, messaging,
connectivity and telemetry groups, and kept widgets (Live Activities, chronod, PosterBoard, navd),
icloud and other on. The list lives in Simlock's config, not in this repo, and changes with it;
`simlock config get ios.slim.categories` prints the groups slim turns off now.

## Decision

- **Every lease the scripts take is slim, unless `WORKOUT_LEASE_MODE=full` asks for full.**
  `detached_lease` in `scripts/sim-lock.sh` passes `--mode` explicitly, so what the scripts print
  stays true if Simlock's default changes. `verify.sh` and `scripts/test-sim.sh` print the mode of
  the lease they took or found. The XcodeBuildMCP hook prints a `--mode slim` lease command and
  the mode of the lease the caller holds.
- **Full is for a service slim turns off, and for the callers kept on it by order.** The Live
  Activity drives in `features/live-activity.md`, `features/lock-screen-logging.md` and the
  locked drive of `features/say-a-set.md` set `WORKOUT_LEASE_MODE=full` from their first verify
  call. `test-sim.sh` asks for full when
  `TEST_RUNNER_WORKOUT_ACTION_BUTTON=1` is set and its selection reaches
  `ActionButtonDictationUITests`, which locks the screen and reads the Live Activity card: `ui`,
  `all`, the `WorkoutTrackerUITests` bundle, or a test ID under that class. Without that variable
  the class's tests skip, so a plain `ui` or `all` run stays slim. A set `WORKOUT_LEASE_MODE` wins
  over both. No other UI test reads the Lock Screen or an activity.
  The smoke tests tap SpringBoard's Open prompt, which is for the app's own URL scheme.
- **Full asked over a held slim lease exits 2.** The message names `simlock release <id>` and
  `WORKOUT_LEASE_MODE=slim`. Running the call on the slim device would miss the service it asked
  for and fail without saying why. A held full lease serves a slim ask. verify's drives, `stop`
  and `release` never refuse on the mode, so `release` stays the way out.

## Considered alternatives

- *Keep every lease full (ADR-0024).* Each agent that never looks at a widget pays for every
  service slim turns off.
- *Swap a held slim lease for a full one.* That releases the device the agent may be designing on,
  and the replacement costs a first boot. The refusal names the release and lets the agent choose.
- *Lease full whenever `VERIFY_LIVE_ACTIVITIES=1` is set.* A drive's lease usually comes from
  `verify.sh build`, which runs before the launch that reads that flag. So build would lease slim
  and the launch would refuse anyway. The feature docs set `WORKOUT_LEASE_MODE=full` for the whole
  drive instead.

## Consequences

- The warm pool now serves two kinds, as ADR-0024 warned. Whichever kind is not warm costs a cold
  boot. Most leases are slim now, so a full lease is the one more likely to cold-boot.
- An agent holding a slim lease that turns out to need full releases it and leases again, which
  costs the host one first boot.
- The Live Activity drives and `ActionButtonDictationUITests` (when it runs) stay on full. The SLIM-1 failure came
  from a slim config that also turned off widgets. A later probe on the config that keeps widgets on
  saw the Live Activity in the Dynamic Island and on the Lock Screen, with its card buttons working.
  These callers stay on full by the coordinator's order, and a later change can move them to slim.
- CI is unchanged. Its runner boots its own slim simulator (ADR-0022).

Supersedes ADR-0024's "Leases are full boots" decision and its amendment's "Leases stay full".
