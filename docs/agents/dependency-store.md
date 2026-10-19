# Dependency store

<!-- doc-symbols: not-in-tree workspace-state.json stringByStandardizingPath info.plist PbxCp.swift -->

`scripts/dep-store.sh` keeps one copy of each large, immutable build input on this Mac and hands
every lane an APFS clone of it. Ten lanes that need the same 384 MB of resolved Swift packages,
or the same 465 MB Core ML model, cost one copy on disk plus about 1.5 MB of metadata per clone,
not ten copies. `scripts/dep-store.sh --help` is the interface; this note is the design.

## Data shape

The store is one directory, `WORKOUT_DEP_STORE` (default `~/Library/Caches/workout-dep-store`).
It sits on the same APFS volume as the worktrees and `~/Library/Developer/Xcode/DerivedData`,
with no symlink in its path, so `cp -c` clones instead of copying.

```text
entries/<key>/payload/   the tree a producer wrote; immutable once published
entries/<key>/meta       key, produced-at, producer pid, the staging path it was produced in
entries/<key>/used       touch file; its mtime is the entry's last clone (the LRU mark)
staging/<pid>.<key>.<rand>/   one producer's private build dir; readers never look here
```

A key is `sha256` over everything that determines the payload's bytes, in a fixed order:
`scripts/dep-store.sh key <file>... -s <string>...` hashes each file's bytes and each string.
For resolved packages the inputs are `Package.resolved` and the Xcode build version
(`xcodebuild -version`), because the resolve depends on both and nothing else that varies
between lanes. Two lanes on different branches with the same `Package.resolved` share one entry.

## Lifecycle

1. **Miss.** `clone <key> <dest>` exits 3 when `entries/<key>` is absent. The caller builds the
   input its usual way, or runs `publish`.
2. **Publish.** `publish <key> <command>` creates `staging/<pid>.<key>.<rand>/payload`, runs the
   command with `DEP_STORE_OUT` pointing at it, writes `meta` and `used`, and moves the staging
   dir to `entries/<key>` with one `rename(2)`. A command that fails or writes nothing publishes
   nothing and the staging dir is removed. A second `publish` of a present key never runs the
   command, so a caller may always publish-then-clone.
3. **Clone.** `clone <key> <dest>` touches `used`, then `cp -c -R entries/<key>/payload <dest>`.
   `<dest>` must not exist; its parent is created. The lane owns `<dest>` outright and may write
   into it. If `cp` fails part way (the entry was pruned under it), `<dest>` is removed and the
   exit is 70, so the caller falls back to a miss.
4. **Prune.** `prune --keep-bytes <n>` removes entries least recently cloned first until the
   entries total at most `n` bytes, skipping any cloned in the last
   `WORKOUT_DEP_STORE_GRACE_MINUTES` (10), and removes staging dirs whose producer pid is dead.

The idempotence test ([principle-make-operations-idempotent](../../.claude/skills/poteto-mode/SKILL.md)):
a rerun of any verb finds nothing left to do or converges. A producer that crashed at any point
left only a staging dir with a dead pid, which the next `publish` or `prune` sweeps; it never left
a partial entry, because the only way into `entries/` is the rename of a finished staging dir.

## Concurrency

- Readers share nothing mutable with each other or with producers: each lane reads only its own
  clone, so no reader needs a lock.
- The only shared write is `rename(staging, entries/<key>)`. It is atomic, and onto a non-empty
  directory it fails with `ENOTEMPTY`, so two producers racing on one key both finish, one wins,
  the loser discards its staging dir and exits 0. The duplicate costs one extra build of that
  input (about 25 s of CPU for a package resolve), and happens only when two lanes miss the same
  new key within a resolve of each other, so a per-key lock is not worth its failure modes.
- Deleting an entry never breaks a lane: an APFS clone keeps its blocks when the original is
  removed. A clone in flight is protected by the grace window, and a prune that still wins the
  race makes `cp` fail, which `clone` turns into a clean miss.
- `used` is touched, never written, so concurrent touches commute.

## Measured

Inside a 20 GB sparse APFS image, `df` deltas (du counts clones at full size, df counts blocks),
one run each, load average 55:

| action | blocks used | wall |
| --- | --- | --- |
| import one SourcePackages entry (393,448 KiB by du) | 395,284 KiB | 1.7 s |
| 10 `cp -c -R` clones of that entry | 15,760 KiB total (1.5 MB each, metadata) | 10.4 s |
| 10 `cp -R` copies of that entry | 3,952,928 KiB | 34.6 s |
| remove the entry while 10 clones exist | frees 1,264 KiB; clones still read | 0.5 s |
| 465 MB random file, 10 `cp -c` | 0 KiB (df moved by -4,936 KiB of noise) | 0.11 s |
| 465 MB random file, 10 `cp` | 4,761,600 KiB | 9.5 s |
| `cp -c` the file into an `.app` then `codesign --force --sign -` | 16 KiB; signature valid | 8.1 s |

A directory clone costs about one second per 400 MB entry of many small files (per-file
metadata); a single large file clones in milliseconds.

Fresh-lane first build (`xcodebuild build-for-testing`, through `scripts/build-slot.sh`, host load
150 to 190 on 12 cores) with the lane's `DerivedData/SourcePackages` pre-seeded by `clone`, versus
a cold DerivedData, alternating, 3 runs each. Every run compiled the same 630 tasks and built
clean; the cold runs each logged 12 package fetches and 12 working copies, the seeded runs none.

| | cold resolve phase | seeded resolve phase | cold, slot to first swiftc | seeded, slot to first swiftc | cold total | seeded total |
| --- | --- | --- | --- | --- | --- | --- |
| run 1 | 15.6 s | 1.8 s | 29.4 s | 17.7 s | 136.3 s | 130.8 s |
| run 2 | 12.9 s | 1.3 s | 23.4 s | 8.7 s | 78.1 s | 78.2 s |
| run 3 | 5.0 s | 1.2 s | 10.7 s | 5.7 s | 72.5 s | 71.3 s |

The resolve phase (`Resolve Package Graph` to `Resolved source packages`) shrinks in every pair,
median 11.6 s saved (range 3.8 to 13.8 s). The total wall time shows no measurable difference at
this load (deltas of -5.5, +0.1 and -1.2 s against run-to-run spread of 60 s), because a build
on a host at load 150 is bounded by CPU scheduling, not by its own phases; CPU time was 166 to
184 s user on both sides. Seeding a lane costs one `clone` of 0.7 to 2.6 s and 1.5 MB of disk,
against 384 MB and a 5 to 16 s resolve per lane today. xcodebuild left the seeded
`workspace-state.json` untouched and wrote only `prebuilts/swift-syntax/603.0.1`. The unit suite
run from the seeded build (`scripts/test-sim.sh --no-build unit`) passed: 1264 tests, 1263
passed, 1 expected failure, 0 failed.

## Consumer: resolved Swift packages

The first consumer is each lane's `DerivedData/WorkoutTracker-<hash>/SourcePackages`. Xcode's
`workspace-state.json` records the artifact bundle's absolute path, so a clone rewrites that
prefix to its own `SourcePackages` path before the first build. The rewrite is required: a seeded
build without it (one run) still skipped the resolve and left the state file alone, but ran the
SwiftLint build tool plugin's binary from the path the state named, which was the producing
lane's DerivedData, so that lane's `lane.sh down` would have broken this lane's builds.

Xcode names the DerivedData dir from the project path after `stringByStandardizingPath`
(a leading `/private` is dropped, so `/private/tmp/x` hashes as `/tmp/x`): MD5 of the path, each
8-byte half read big-endian and written as 14 base-26 letters. The computation matches every
DerivedData dir on this Mac with an `info.plist` (8 of 8) and the two the experiment created, and
costs about 50 ms in Python (20 runs in 0.99 s at load 190). The alternative,
`xcodebuild -showBuildSettings`, took 34.0 s wall and 9.2 s CPU on a worktree with no
DerivedData (one run, load 95 to 213), because it resolves and extracts every package to answer,
leaving a 396 MB DerivedData behind: the cost the store exists to avoid.

Integration (not wired yet; a worker is editing `test-sim.sh`): before `build-for-testing`, when
`<dd>/SourcePackages` is absent, `clone` the key for `Package.resolved` plus the Xcode build
version into it and rewrite the artifact path. After a build that resolved cold, `publish` the
key with `cp -c -R <dd>/SourcePackages/ "$DEP_STORE_OUT"` as the producer, which costs the lane
about one second and nothing on disk.

## Consumer: a large model file

A 465 MB Core ML model does not belong in Copy Bundle Resources: Xcode's copy tool reads and
writes every byte (swift-build `PbxCp.swift`), so each DerivedData and each embedding bundle
holds a full copy. Instead:

1. The model lives in the store under a key of its own content hash (or the URL and version it
   was fetched from); `publish` downloads it once.
2. A Run Script build phase clones it into the product:
   `scripts/dep-store.sh clone "$MODEL_KEY" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Model.mlmodelc"`
   after removing the previous copy. Code signing seals the clone like any file (measured above).
3. The phase runs only for configurations that ship the model, and is skipped for Simulator test
   runs (`[ "$PLATFORM_NAME" = iphonesimulator ] && exit 0`), where the tests use a fixture.

`simctl install` already clones the app from DerivedData, so the model then costs one copy on the
Mac however many lanes and simulators hold it.
