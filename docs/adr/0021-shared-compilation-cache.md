# A shared compilation cache for package targets only

Agents work in parallel lanes, each a worktree with its own DerivedData (ADR-0020). A lane's first
`test-sim.sh` build compiles everything, about 190 to 210 CPU seconds, on a host whose CPU limits
throughput. Xcode 27 can replay a compile from a content-addressed cache (CAS) instead of running it.
Xcode's default CAS, `~/Library/Developer/Xcode/DerivedData/CompilationCache.noindex`, serves
every project on the default DerivedData root. Lanes still could not share entries. A cache key holds
absolute paths, and two roots differ per lane: the checkout, and its
`DerivedData/WorkoutTracker-<hash>` dir, which also holds SourcePackages. Xcode's prefix mapping can
rename both to fixed names (`/^wt`, `/^dd`). A probe found that mapping only one of them leaves 39 to
91 misses. Every package `CompileC` also misses unless the clang map names the checkout, because
`-fcoverage-compilation-dir` does.

We measured on 2026-10-19 on the Mac mini from ADR-0020, with Xcode 27.0 (27A266a), at 1-minute
loads of 6 to 730 from other sessions. Each row runs test-sim.sh's `build-for-testing` line under a
build slot, in a fresh `scripts/lane.sh up` lane, or in a warm lane that had built and then took an
edit. CPU seconds are user plus system from
`/usr/bin/time -l`. On and off ran alternately, so drift reaches both. Wall time is noisier. These
runs used Xcode's default CAS, before the decision below gave the repo its own.

| Configuration and scenario | Runs | Hits | Misses | CPU s, median (range) | Wall s, median (range) |
|---|---|---|---|---|---|
| Every target cached, cache off | 3 | 0 | 0 | 209.5 (197.1 to 212.5) | 122.5 (71.5 to 134.6) |
| Every target cached, same commit as an earlier lane | 3 | 381 | 0 | 39.6 (39.6 to 40.6) | 37.5 (32.7 to 66.9) |
| Every target cached, one line added to `RPETable.swift` | 3 | 342 | 39 | 171.0 (170.3 to 183.0) | 96.9 (67.2 to 123.3) |
| Every target cached, warm lane, one member added, on | 3 | 0 | 29 | 110.8 (110.4 to 122.0) | 18.7 (16.7 to 37.3) |
| Same edit, warm lane, off | 3 | 0 | 0 | 16.1 (13.8 to 17.2) | 11.5 (9.9 to 15.0) |
| Packages cached, empty cache | 1 | 18 | 428 | 197.6 | 30.5 |
| Packages cached, cache off | 3 | 0 | 0 | 188.5 (186.6 to 188.6) | 34.8 (27.9 to 35.8) |
| Packages cached, same commit | 3 | 315 | 0 | 176.2 (166.1 to 178.4) | 39.9 (26.1 to 45.3) |
| Packages cached, one line added to `RPETable.swift`, on | 3 | 315 | 0 | 167.9 (167.2 to 176.0) | 28.7 (28.0 to 39.4) |
| Same edit, off | 3 | 0 | 0 | 191.7 (187.3 to 196.4) | 36.1 (29.8 to 39.5) |
| Packages cached, warm lane, one member added, on | 5 | 0 | 0 | 14.6 (13.7 to 19.0) | 10.9 (9.7 to 17.4) |
| Same edit, warm lane, off | 5 | 0 | 0 | 14.1 (13.6 to 15.4) | 10.2 (9.6 to 11.7) |

What the numbers say:

- **Caching every target makes a lane's first build five times cheaper, and breaks 13 unit tests.**
  A compile that sees the checkout as `/^wt` bakes `/^wt/...` into `#filePath`. `RepositoryFiles`
  finds the repository by walking up from `#filePath`, so each test that reads a repository file
  fails with `No Package.swift in any directory above /^wt/Tests/Support/RepositoryFiles.swift`.
  The same 13 failed after a one-line edit made `WorkoutTrackerTests` recompile, so the mapping
  causes it, not a replayed entry. `strings` counts 152 `/^wt` paths in that bundle and 19 in the
  snapshot bundle, which finds its reference images through `#filePath` too. The same lane with the
  cache off passed all 1,263.
- **Caching every target makes the warm edit loop seven times dearer in CPU.** After an edit that
  adds a member to a library type, the cache-off lane recompiled 3 test files. The cache-on lane
  recompiled all 181 files of `WorkoutTrackerTests` and all 47 of `WorkoutTrackerSnapshotTests`.
  The maps cause it, not the cache. One run each of the same edit: with every target cached and
  no maps, 5 misses and 14.4 CPU s; with the cache off, 14.0; with the maps, 39 misses and 133.8.
  A guess at why: the driver's dependency records hold mapped paths it cannot match to the sources.
- **An edit to the app module misses on every batch of it.** A Swift compile's key covers every source
  in its module, and `Sources/WorkoutTracker` compiles into the app target (ADR-0017). One body-only
  edit missed only the app's 13 tasks (68.8 CPU s, one run). An edit that adds a member changes the
  emitted module, so both unit test bundles missed too.
- **Packages alone save 12 to 24 CPU seconds, 6 to 12% of a fresh lane's build.** Every package
  compile hit, whether or not the lane's commit edited the app. In both scenarios the on range sits
  below the off range, so the gap is real, but the app module and the test bundles are most of the
  work. Wall time showed no clear difference at this load. Project targets built as with the cache
  off: the warm edit loop's ranges overlap, the unit suite passed 1,263, and the built bundles hold
  no mapped path. An empty cache costs what the cache off does. It logged 446 cached tasks, 118 of
  them explicit Clang module builds, where later lanes logged 315 hits and no miss.

## Decision

- **Only Swift package targets use the cache.** `scripts/compile-cache.sh` sets
  `COMPILATION_CACHE_ENABLE_CACHING` to `$(WORKOUT_COMPILE_CACHE_$(PROJECT_NAME:c99extidentifier):default=YES)`
  and `WORKOUT_COMPILE_CACHE_WorkoutTracker=NO`. Xcode expands it per target, so the `WorkoutTracker`
  project's targets compile uncached and keep their real paths.
- **The helper is the one source of the settings.** `test-sim.sh`, `verify.sh`'s builds, and
  `check-each-commit.sh` source it and pass `compile_cache_settings` to `xcodebuild`.
  `WORKOUT_COMPILE_CACHE=0` leaves it empty.
- **Xcode expands the two roots.** The maps are `$(WORKSPACE_DIR:dir:standardizepath)=/^wt` and
  `$(OBJROOT:dir:standardizepath:dir:standardizepath)=/^dd`, passed single-quoted. `SRCROOT` names
  the package checkout in a package target, so it would not do. The prefix map Xcode wrote for
  each of the 40 targets held the lane's own two paths. No shell code predicts the DerivedData dir's
  name.
- **The default DerivedData root stays.** `lane.sh down` and the prune scripts still find a lane's dir
  by its `WorkspacePath`. The CAS path is passed explicitly, so `verify.sh install`'s app-cache
  builds, which pass `-derivedDataPath`, share it too.
- **The CAS is the repo's own.** It is
  `~/Library/Developer/Xcode/DerivedData/WorkoutTracker.CompilationCache.noindex`, one per host, and
  every worktree of the repo shares it, because the maps keep paths out of the keys. Xcode's default
  CAS also holds other projects' entries, and those projects and other sessions write and prune it:
  its size moved during cache-off runs, and the 2 GB limit below made our builds prune their entries
  too, from 3.92 to 1.75 GB within one build. Beside the default CAS, deleting DerivedData resets it
  with every other build cache. The dot, not a hyphen, keeps it out of the `WorkoutTracker-*` globs
  the scripts use to find a worktree's DerivedData.
- **The cache is capped at 2 GB.** An empty CAS grew to 316 MB from one cold package-only build,
  and each later fresh lane added about 47 MB though every package compile hit. Xcode starts a new
  generation at about half the limit and keeps the two newest, so 2 GB holds the working set three
  times over and settles near 2 GB. The limit now prunes only this repo's entries. `df -h /` showed
  13 to 29 GiB free during the measurements, and the default limit, half of the cache plus free
  space, would let it take 7 to 15 GiB.
- **Diagnostic remarks stay on.** A build log then says `Cache hit` or `Cache miss` per cached task.

## Considered alternatives

- *Cache every target.* It is the prize in the table, but it needs two changes first. The tests
  must stop reading `#filePath`: `test-sim.sh` could pass the checkout in an environment variable,
  and snapshot tests could name their reference directory. And the warm edit loop must not pay
  seven times the CPU for the maps. Until both hold, it costs more than it saves. Caching the
  project's targets without maps is harmless but useless: their keys hold the lane's own paths, so
  no other lane hits them.
- *Compute the DerivedData dir's name in shell.* That copies Xcode's hash of the project path, which
  Xcode may change. The macros need no copy.
- *A fixed `-derivedDataPath`.* A per-lane path moves the module caches out of the shared root and
  hides the lane from `lane.sh down`. One path for every lane lets lanes overwrite each other's products.

## Consequences

- A fresh lane saves the package compiles, 12 to 24 CPU seconds. Nothing else changes for it.
- CI is unchanged. It caches every target with no maps and pins its paths under `runner.temp`.
- Worktrees on an older commit build with their own `test-sim.sh`, without the cache, until they
  rebase.
- `check-each-commit.sh` builds for a generic simulator destination, so its package keys may differ
  from a lane's. This is unmeasured.
- The limit is soft. Xcode collects old generations during a build, from the first cached task,
  but starts a new one only when it closes the CAS and no other process holds it open. While lanes
  overlap, the cache can grow past 2 GB until the last of them exits. Concurrent builds share the
  CAS safely; it is built for many processes.
- The CAS holds only this repo's package compiles, from every worktree on the host. Deleting it
  costs one cold build.
