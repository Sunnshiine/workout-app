# Eval: a base-vs-head CLI parity harness

<!-- doc-symbols: not-in-tree manifest.json workbook.json -->

Should WorkoutTracker's verification loop run one script of `workout` commands through a binary
built at the merge base and one built at head, and fail on any difference? This eval measured it
on 2026-11-02 against `origin/main` at d21de386.

**Recommendation: adopt it in a narrower form.** Keep `scripts/parity.sh` as an opt-in local
tool for refactors whose output reaches the disk or the CLI's wire contract. Do not add a CI job
or a blanket AGENTS.md rule. Across 78 compiled mutants, `swift test` killed 64 and parity
caught 26. Only one mutant was caught by parity alone, and no historical regression would have
been caught by it. The case for keeping it is that agents already hand-run this check, and the
harness makes it rerunnable at about 25 s.

## The harness

`scripts/parity.sh <base> [<head>] [scenario.txt ...]` builds `workout` at both commits in a
`scripts/scratch-tree.sh` slot. It caches each binary by tree hash under `.build/parity/bin`. Head
defaults to the working tree, uncommitted edits included. It runs each scenario under
`scripts/parity/` through both binaries and prints a unified diff of the two transcripts. A
transcript holds each command, its exit code, stdout, stderr, and a digest of `workbook.json`,
`settings.json`, and `manifest.json` after every step, plus the full files at the end.

A scenario line is a CLI command, or one of two directives. `coach <cell> <value>` edits the
workbook as the coach would, which is the gap the CLI has no verb for. `observe` prints `status`,
`session` for every Session, and `sheet`. The corpus has 8 scenarios and about 270 commands:

- `arc` is the README arc.
- `every-scenario` covers all 11 `WorkbookScenario`s.
- `edits` covers clear, Spoken Sets, bad addresses, and a bad Set Log.
- `navigation` covers make-current, Move On, and `sync --viewing`.
- `differential-replays` covers `DifferentialStateTests`' replay and known-divergence scripts.
- `conflict` covers a refused write.
- `load-suggestions` and `final-set` were added after the planted-bug run (see below).

**Nondeterminism, removed at the source.** Both binaries run one after the other in the same
home path, which is wiped between runs. Each run uses `WORKOUT_NOW`, `TZ`, and `LC_ALL` pinned.
An A/A run on d21de386 was byte-identical with **zero masks**. The `"home"` path mask from the
first A/A trial is not needed. `store.sqlite` is not compared, because what it holds reaches the
transcript through `status` and `session`. The only exclusion the harness carries is the skew
rule. A scenario is skipped, and counted, when base rejects a command as a usage error (exit 64)
that head accepts.

**Proving the oracle.** The planted bugs below show the harness sees what the CLI reaches. It
caught M01 (every upsert writes an empty cell), M05, M09, M11, M12, and others. The 31-commit sweep showed old
binaries really ran. 197 of 238 steps exited 0 at the oldest pair, and 235 of 245 at the newest.

## Results

### Historical replay

A subagent classified 35 `fix` commits on `Sources/WorkoutTracker/` since the CLI landed
(0cabaa77, #532, 2026-09-14). It used commit messages, PR bodies, linked issues, and `git blame`
at each fix's parent.

| Finding | Count |
|---|---|
| Refactor or perf regressions that reached trunk | **0** |
| Refactor or perf bugs fixed inside their own PR (#825, #829 ×2, #839) | 4, none CLI-observable (cache invalidation on a thrown save, animation, SwiftUI observation) |
| Latent test-only defect from a refactor (#1008) | 1, not CLI-observable |
| Fixes that raw blame wrongly pins on a refactor (#976, #948, #1018, and others) | 3+ |
| Regressions from `feat` commits | about 7, 1 CLI-visible (#979, a duplicated refusal line) |

I checked two citations myself. #598's body says `workout` from the branch and from `origin/main`
"print byte-identical JSON across nine scripted steps". #951's body says the pin encoding "stays
byte-identical". Agents already run this check by hand on refactors, which may be part of why
none of these regressions reached trunk.

**Sweep over every refactor/perf commit.** I ran parity on each of the 31 first-parent
`refactor`/`perf` commits touching `Sources/WorkoutTracker/` since #634 (commit^ against commit).
27 were clean. 4 differed, and none was a bug or noise:

| Commit | Diff | Verdict |
|---|---|---|
| 96d99a87 (#949), 36e4d74d (#984), d9c4b0df (#1002) | `init --scenario` accepts a new scenario | Intended additive change. A per-scenario split of `every-scenario` would turn these into skips |
| b9d1482a (#1009) | A fixture Set Log became a real cell (K17), so the CLI reads it as logged | Intended. The PR fixes #1000 under a `refactor` title |

So the rate of false positives from nondeterminism was 0 of 31. Every diff was a real behaviour
change in a PR titled `refactor`, which a reviewer would want to see.

### Planted and generated bugs

Each mutant was applied in a scratch worktree. Then `swift test` ran (1,821 tests), and then
`scripts/parity.sh HEAD`. Three sources:

- **Planted.** A fresh subagent wrote 20 single-line "refactor slips" in mutate.sh sed form, 4 per
  area. It saw only the target files, never the corpus or the tests.
- **Generated.** 40 picked at random (seed 20261102) from the 322 mutants `scripts/mutants.awk`
  makes over SheetWriter, SyncCoordinator, WorkoutStore, flush ordering, the parsers, load
  suggestions, RPETable, and Progress/. This set has no planter bias.
- **CLI layer.** 20 picked at random (seed 7) from the 125 mutants over `Sources/WorkoutCLI/` and
  `Sources/WorkoutTracker/Application/`.

| Set | Compiled | `swift test` kills | Parity catches | Both | Parity only | Tests only | Neither |
|---|---|---|---|---|---|---|---|
| Planted | 20 | 20 | 9 | 9 | 0 | 11 | 0 |
| Generated, core | 39 | 32 | 12 | 12 | 0 | 20 | 7 |
| Generated, CLI and facade | 19 | 12 | 5 | 4 | **1** | 8 | 6 |
| **Total** | **78** | **64** | **26** | **25** | **1** | **39** | **13** |

**The one unique catch** is C08, which changes `Manifest.currentVersion` from 2 to 3 in
`Sources/WorkoutCLI/Home.swift`. That is a persisted-format change. No test pins the number, and
parity sees it in every `manifest.json`. This is the class where parity adds value: a byte on disk
or on the wire that no test asserts.

**Why parity misses what tests kill.** Of the 11 planted misses, these are corpus gaps a scenario
can close:

- M18, the history basis picking the lowest-RPE Set Log.
- M10, clearing the final Set expecting an empty RPE cell.
- M02, compact Set Log list placement.
- M03, a write in Week 2.
- The CLI's own refusal dedup, C06 and C18. It needs a `sync` that itself refuses a write.

The rest are paths the CLI cannot reach:

- M07, a failed batch write. It needs fault injection.
- M04, hidden rows within one flush.
- M06, the Exercise History fill, which runs after the CLI process exits.
- M15, an error-kind swap the message hides.
- M13 and M19, which need inputs the fixtures don't have.

Two scenarios written after seeing the misses, `load-suggestions` and `final-set`, raised planted
catches from 9 to 12 (M02, M10, M18). That shows the corpus is cheap to extend. It is not
unbiased detection.

**The 13 that neither caught.** These are G02, G11, G17, G27, G30, G36, and G39 in the core set,
and C03, C04, C09, C14, C19, and C20 in the CLI set. I read the seven core ones:

- Three change nothing the CLI exposes. G27 is the write-target audit fetch. G02 and G30 are
  internal counters.
- Two are likely equivalent. G36 cannot change behaviour, because the comparator orders by
  `(rpe, offset)` and offsets never repeat. G17 differs only for loads between 0 and 1 lb.
- G39 needs a Training Max header on row 0.
- G11's open-Exercises filter is likely equivalent, but I did not prove it.

I did not read the six CLI-set survivors one by one. From their sites, C14 is in `hear`, which
the corpus never runs, and C19 is the internal-error exit code, which no scenario reaches.

### Agent A/B on a real refactor

Two fresh agents on the same model got the same organic prompt. The task was points 1, 2, and 5
of #1132: give the Sync Outcome one verdict that `ApplicationError`, `SyncCommand`, and
`FlushCommand` ask, with no exit code or message moving. Checkout A had the harness and one
AGENTS.md line telling refactors to run `scripts/parity.sh origin/main`. Checkout B had neither.

| | Tokens | Tool calls | Wall-clock | `swift test` | Parity on its commit (my run) | Behaviour change shipped |
|---|---|---|---|---|---|---|
| A, with harness | 89,583 | 31 | 9.5 min | 1,822 pass | 8 clean | No |
| B, without | 72,352 | 22 | 6.1 min | 1,822 pass | 8 clean | No |

A spent about 6 calls on the harness and about 5 on a whole-tree `scripts/lint.sh` failure. My
harness caused that failure, because `.build/parity` was in neither list in
`scripts/build-dirs.sh`. It is fixed on this branch. Net harness overhead on this task was about
+17k tokens (+24%) and +3.4 min, with no defect prevented. B relied on `PublicSurfaceTests` and
the CLI binary tests, which already pin every `syncFailed` row and the exit codes. This is one
pair, and token spread between runs is often wider than this gap, so treat it as an anecdote. The
prompt-side cost is fixed: a clean run prints one line, and a dirty run prints a unified diff.

## Cost

| Item | Measured or estimated |
|---|---|
| Cold `workout` build, local 12-core | 9.5 s wall, 36 s CPU (measured, 1 run) |
| Warm rebuild after a one-file touch | 2.0 s, and 0.6 s no-op (measured) |
| One sweep pair: build two neighbouring commits plus run 6 scenarios | 20 to 38 s, median about 26 s (measured, 31 pairs, under mutant-run load) |
| Warm run, 8 scenarios, binaries cached | 22.2, 22.5, 23.0 s (measured, 3 runs, load average about 8) |
| `swift test`, warm | 22.9 s for 1,821 tests (measured, 1 run) |
| A CI job on `refactor`/`perf` PRs | About 2 to 3 runner-minutes: 20 s checkout, two cold builds on a smaller hosted runner, 25 s run (estimate, not run on CI) |
| CI wall-clock added | About 0. It would run beside `visual-tests`, whose median critical path is 567 s (from `scripts/ci-timing.sh --branch main --last 3`) |
| PR volume it would apply to | About 7 to 7.5 refactor/perf PRs a week (49 to 52 since 09-14) |
| Maintenance | One ~150-line script plus corpus. The skew rule breaks when a scenario is renamed, and every new CLI verb needs a scenario line. This eval found 1 harness bug (the build-dirs list) and 1 trap (local `main` was weeks stale) |

The run time is bounded by roughly 540 process spawns in sequence plus a Python call per
`observe` and `coach`. The build is not the limit. Running scenarios in parallel would bring it
near 5 s on this machine (estimate).

## Improvements

1. **Default the base to `git merge-base origin/main HEAD`.** Local `main` in this checkout was
   at d6ea9e28, weeks behind. `parity.sh main` would have printed weeks of real changes as
   regressions.
2. **One scenario per `WorkbookScenario`.** This turns additive scenario names into skips
   instead of diffs. Three of the four sweep diffs were this.
3. **Run scenarios in parallel**, each with its own home, to cut the 22 s run.
4. **Corpus additions for the measured gaps:**
   - a `sync` that itself refuses a write (C06 and C18)
   - writes in Week 2 and beyond (M03)
   - compact Set Log lists (M02)
   - hidden rows (M04)
   - a Training Max header on row 0 (G39)
   - `hear` with a fixture recording
5. **What the CLI should expose for parity to see more:**
   - `pending-writes` and the audit ledger (G27), which the README already names as next in line
   - a fault switch for the local Sheet client, such as a failed batch or unreachable (M07, `flush` exit 3)
   - a way to run the Exercise History fill to completion before exit (M06)
   - log lines, which it prints none of today
6. **Masks needed: none.** Keep it that way by removing nondeterminism at the source (fixed home
   path, pinned clock, TZ, and locale) rather than masking.
7. **Receipts.** Wrap a run as `scripts/receipt.sh parity -- scripts/parity.sh <base>`, so a
   "byte-identical" claim in a PR body, as in #598 and #951, becomes checkable.

## Recommendation

**Adopt in a narrower form:**

- Keep `scripts/parity.sh` and its corpus (this branch) as a local tool.
- Name it in `docs/TESTING.md` and `Sources/WorkoutCLI/README.md` as the way to back a
  "behaviour unchanged" claim. It fits best on refactors that touch `Sources/WorkoutCLI/`, the
  `WorkoutApplication` facade, or anything that encodes `manifest.json`, `settings.json`,
  `workbook.json`, or Sheet cell text.
- Do not add a CI job, and do not add a blanket AGENTS.md rule.

Why:

- **Catch rate.** Its marginal catch rate over `swift test` is 1 in 78 mutants, and 0 in 7 weeks
  of history. `swift test` kills 64 of 78 and parity catches 26. Per-PR CI minutes and a 24%
  token surcharge on every refactor would buy almost nothing.
- **The class it uniquely covers is real and untested.** Persisted format and CLI wire bytes
  (C08) are exactly what ADR-0015 calls a contract.
- **It is quiet.** It raised 0 false positives from noise across 31 historical refactors and 4
  real behaviour changes inside `refactor` PRs. A reviewer can trust a red result.
- **Agents already do this by hand** (#598, #951, #948). A rerunnable script with a receipt is
  cheaper than an ad hoc one and leaves evidence.

Reopen the CI question if the CLI gains fault injection and the diagnostics verbs (Improvement 5),
or if a refactor-caused regression reaches trunk through a path the CLI reaches.

## Method notes and spend

- Artifacts: the harness and corpus are `scripts/parity.sh` and `scripts/parity/`. The A/B commits
  are 4c014c9e (branch `sync-verdict-a`) and 35dcc994 (branch `sync-verdict-b`), both local.
- Mutant results were kept in `/tmp/parity-mutants/` for the session and are not committed.
  Every row above can be reproduced with `scripts/parity.sh HEAD` after the sed or line change.
- Timings ran while other work shared the machine (load average 8 to 46), so wall-clock numbers
  are upper bounds.
- The eval itself took 79 min of wall-clock. The main thread made 87 API calls with 47k output
  tokens, 152k cache-write tokens, and 9.6M cache-read tokens. Four subagents used 399k tokens:
  the history miner 121k, the bug planter 116k, and the A/B arms 90k and 72k.
