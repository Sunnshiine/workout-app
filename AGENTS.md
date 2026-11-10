# AGENTS.md

WorkoutTracker is an iOS client for powerlifting athletes. It surfaces and logs the workouts a
coach manages in a Google Sheet. The Sheet is the single source of truth and the app is a
read-write client with a local cache (ADR-0001). `CLAUDE.md` is a symlink to this file.

## Sources of truth

Each of these wins over anything written here. Read the one that governs the work before starting.

- `CONTEXT.md` names every domain term, and with the area files it indexes, the synonyms to avoid.
  Use its words in code, tests, and issues.
- `docs/adr/` records decisions. Read the ADRs for the area you change. If your change contradicts
  one, say so in the PR instead of overriding it.
- `PRODUCT.md` and `DESIGN.md` govern product and UI work. Before changing anything the athlete
  sees, run the `product-design` skill (`.agents/skills/product-design/SKILL.md`), which applies
  them and turns the operator's design feedback into rules.
- `CODING_STANDARDS.md` is the review standard. Read it before changing a store, a coordinator, a
  View's logic, or a test, and apply it at review.
- `.swift-format` and `.swiftlint.yml` own formatting and every mechanical rule.
- `docs/TESTING.md` owns the change-risk gate and flake hunting. `tools/crap/README.md` and
  ADR-0016 own the gate's counting rules.
- `Sources/WorkoutCLI/README.md` owns the `workout` CLI. ADR-0015 records the boundary it runs on.
- `.agents/skills/verify/SKILL.md` drives the app on the simulator and captures proof. Read the
  matching file under `.agents/skills/verify/features/` before driving.
- `.agents/skills/simlock/SKILL.md` governs every simulator. Read it before your first simulator run
  in a session. ADR-0024 records why.
- Edit project skills under `.agents/skills/`. Each `.claude/skills/<name>` is a tracked symlink
  to `.agents/skills/<name>/`, not a copy.

## Repository map

The directory a file sits in decides which builds compile it (ADR-0017). These entries are stable;
the folders inside them move, so read the tree instead of a copy of it.

```text
App/                     The iOS app alone: entry point, Views, Live Activity controller, Google
                         sign-in, assets. Outside the package, so swift test never sees it.
Sources/WorkoutTracker/  The library, compiled into the app, the CLI, and swift test: the domain
                         model, Sheet parsing, sync and stores, session and progress logic, the
                         fixtures, and WorkoutApplication.
Sources/WorkoutCLI/      The workout executable. In neither the app nor the widget.
WorkoutShared/           Live Activity attributes and views, and the fonts, compiled into the app and
                         the widget.
WorkoutWidgets/          The widget extension.
Tests/                   Unit/ and Component/ run under swift test. UI/ and Visual/ run on the
                         simulator only. Support/ holds the fakes and fixtures both runs share.
tools/crap/              The CRAP scorer, its own package, run through scripts/crap.sh.
```

`App/`, `Sources/WorkoutTracker/`, `WorkoutShared/`, `WorkoutWidgets/`, and the folders under
`Tests/` are Xcode buildable folders. A Swift file added there compiles into its target with no
project edit, and Xcode copies every other file in the folder into the bundle. To keep a file out
of the bundle, add a membership exception in the project, as each `Info.plist` has.

## Boundaries

- UIKit and other iOS-only APIs belong in `App/`. Every guard, calculation, and branch that
  decides behaviour belongs in `Sources/WorkoutTracker/`, where `swift test` and the CLI reach it.
- `WorkoutApplication` is the composition root and the public facade. The app and the CLI both
  build on it (ADR-0015).
- The Sheet is written only through `SyncCoordinator` and its pending-write queue (ADR-0006). The
  write path is flat, with no `Sync/` folder: `Stores/WorkoutStore.swift` queues a `PendingWrite`
  (`Models/PendingWrite.swift`), `Stores/SyncCoordinator.swift` flushes the queue, and
  `Sheets/SheetWriter.swift` plans each write to a cell. All sit under `Sources/WorkoutTracker/`.

## Commands

```bash
scripts/build-slot.sh swift test                  # unit + component; no Secrets.xcconfig needed
scripts/build-slot.sh swift test --filter ActiveSetFocusManagerTests  # one file's tests, about a second
scripts/lint.sh [file.swift ...]                  # what CI runs, the line below included (the whole-tree run needs `gh auth login`); or SwiftLint on just those files; --fix autocorrects SwiftLint first
scripts/swift-format-changed.sh [--fix] [<base>]  # swift-format the Swift files this branch changes, as CI does
scripts/crap.sh gate                              # the change-risk gate CI runs (ADR-0016)
scripts/test-sim.sh unit                          # simulator suites from one build: unit | visual | ui | all; leases its simulator from Simlock
scripts/test-sim.sh --sim <UDID> unit              # run on the simulator of a Simlock lease you already hold, such as verify's
scripts/test-sim.sh --no-build WorkoutTrackerUITests/WorkoutTrackerUISmokeTests/testCurrentSessionLogsFirstSetAndAdvancesActiveSet
scripts/tests-for.py App/Views/ActiveSetCard.swift  # test-sim.sh IDs of the suites covering a file, or a test function's full ID; no argument: this branch's files
scripts/build-slot.sh xcodebuild build-for-testing -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'generic/platform=iOS Simulator' \
  -skipPackagePluginValidation -skipMacroValidation   # the app and every test bundle; boots and runs nothing
scripts/flake-hunt.sh --repetitions 1000 SyncCoordinatorTests   # repeat a concurrent test under load
scripts/changed-tests.sh                           # the tests this branch changed; what CI's flake guard repeats under load
scripts/mutate.sh --diff origin/main                # mutants on your changed lines, run in a scratch tree; --sim <UDID> reaches App/
scripts/mutate.sh --filter RPETableTests Sources/WorkoutTracker/RPETable.swift '6s/6...10/7...10/'
                                                    # one hand-written mutant (sed on line 6); a test must fail: killed good, SURVIVED bad
scripts/check-each-commit.sh origin/main..HEAD     # builds and tests every commit of a stack, one line each
uv run python3 <script.py>                          # with Pillow and numpy from pyproject.toml; in Claude Code a bare python3 is already this .venv
```

Run every `swift build`, `swift test`, or `xcodebuild` build as `scripts/build-slot.sh <command>`,
which holds a host-wide `hostgate` slot (pinned in `scripts/hostgate-version`); scripts do the same,
and `scripts/lint-build-slots.py` fails one that does not. A hook refuses the raw form.
XcodeBuildMCP builds and runs only on a simulator your Simlock lease holds,
and `scripts/sim-mcp-hook.py` refuses any other naming the lease command. To see the app,
`verify.sh launch session` leases a simulator and prints its UDID. Set it with XcodeBuildMCP's
`session_set_defaults {simulatorId}` alone, and `screenshot`, `snapshot_ui` and `touch` (down and up) drive it.

The headless CLI drives the real stores against a local workbook and prints JSON, in milliseconds,
with no simulator and no Google credentials:

```bash
scripts/build-slot.sh swift build --product workout && export PATH="$PWD/.build/debug:$PATH"
export WORKOUT_HOME=$(mktemp -d) && workout init --scenario fresh-block
workout log w1d1.e0.s0 185x5@8 && workout flush && workout sheet --cell K15   # "185x5@8" landed
```

## Verification

Run `scripts/lint.sh` and `scripts/build-slot.sh swift test` before finishing. On every PR, CI runs those, the CRAP
gate, a flake guard that repeats the tests the PR changed under load, the simulator-hosted unit
and component suite, the visual gate, and swift-format on the Swift files the PR changes. A PR
titled `fix(`, `fix:`, or `fix!:` also gets the advisory `mutants` job, which comments the mutants
of its changed `Sources/` lines that no test kills and never fails. CI
runs `KeyboardLaneUITests` on a PR that touches what it reaches (`scripts/keyboard-lane-paths.sh`)
or on `gh workflow run ci.yml --ref <branch> -f keyboard-lane=true`. It runs the rest of
`WorkoutTrackerUITests` only on request, with
`gh workflow run ci.yml --ref <branch> -f ui-suite=true` (#662). A PR
whose changed paths all sit in `ci.yml`'s `paths-ignore` (Markdown, `docs/`, agent files, and
more) starts no CI run. Every PR starts a Receipts run, and when no other workflow runs,
`scripts/ci-wait.sh` exits 3.

- Write each verification result the PR body cites with `scripts/receipt.sh <name> -- <command>`
  and paste the block as printed. The Receipts workflow fails a receipt from a dirty tree, from a
  commit CI does not have, with a nonzero exit, or from code that differs from the head outside
  `docs/`, and a receipt named `lint` on any change. It also fails a commit message's `Fixes #N`
  that the body does not repeat. Rerun the receipts after you merge trunk code. Put a red run
  from before a fix in prose.

- Neither test run is a superset of the other. `swift test` compiles `Sources/` alone, so a green
  run does not prove the app compiles. `scripts/test-sim.sh unit` compiles the app and skips the
  macOS-only CLI suites (`WorkoutCLIBinaryTests`, `CLIFailureTests`). Before pushing a diff that
  touches `App/`, run the simulator suite as well. A signature change under `Sources/` or
  `WorkoutShared/` can break `App/`, `Tests/Visual/`, and the app-hosted unit tests, which
  `swift test` never compiles. Before pushing one, run the `build-for-testing` line above.
- Run simulator suites through `scripts/test-sim.sh`. A bare `xcodebuild test` fails plug-in
  validation on a fresh machine and can hang collecting diagnostics after a failure.
- Every simulator comes from a Simlock lease (`.agents/skills/simlock/SKILL.md`). `test-sim.sh`
  and `verify.sh launch` take one for you. Never create, boot, shut down, erase, or delete a
  simulator yourself, and never name one by model in a `-destination`; `scripts/lint.sh` fails on
  each. A raw `xcodebuild` or XcodeBuildMCP call takes no lease, so give it `id=<UDID>` of a lease
  you hold.
- You hold one lease at a time. When you already hold one, `test-sim.sh` exits 75 and names it;
  pass it as `scripts/test-sim.sh --sim <UDID> ...`. While Simlock has no free simulator it waits
  up to `WORKOUT_ADMIT_WAIT` (540 s), then exits 75. It exits 78 without `simlock` on PATH.
- Concurrent simulator runs each need their own worktree. `scripts/lane.sh up <name> <commit>`
  makes one (`docs/TESTING.md`); Simlock gives each run its own simulator.
- `test-sim.sh` exits 69 when the simulator broke rather than a test, as when a launch returns no
  process handle (#537), or when Simlock took its lease back. Rerun the same command; do not debug
  the app.
- macOS has no `timeout`, so `timeout N cmd` exits 127 without running the command.
- The `WorkoutTracker` scheme launches against local fixtures (`-UITEST_FIXTURE true`), never the
  live Sheet. `Copy of WorkoutTracker` runs live.
- Visual Baselines are recorded on the CI runner, not locally, because renders differ across
  machines (ADR-0007; the recipe is in `docs/TESTING.md`). After a rebase that conflicted only in
  baselines, take trunk's side, push, and run `scripts/rerecord-snapshots <paths>`.

## Worktrees and landing

- `Secrets.xcconfig` is git-ignored and needed only for Xcode app builds; `swift test` runs without
  it. `scripts/install-worktree-bootstrap.sh --source <path>` installs the post-checkout hook that
  copies it into every new worktree. In a worktree the hook did not run in, run
  `sh .githooks/post-checkout` once.
- XcodeBuildMCP session defaults point at the primary checkout. From a worktree, pass
  `-project <worktree>/WorkoutTracker.xcodeproj` explicitly. The `.mcp.json` pin stays at 2.7.0 or
  later, because older builds fail every accessibility call on Xcode 27.
- Land with `scripts/ci-wait.sh N` and the merge command it prints. Leave out `--delete-branch`.
  GitHub deletes the remote branch itself, and the flag switches whichever worktree holds the
  branch onto `main`. `scripts/prune-merged-worktrees.sh` lists worktrees whose PR has merged or
  closed, and clean lane worktrees idle past `--lane-idle-days`, and removes them only under
  `--apply`.
- CI's lint job and `scripts/ci-wait.sh` run `scripts/landing-reverts-main.py`, which fails a PR
  whose landing would undo one of the last 40 commits on its base, as #1012's merge did. For a
  deliberate revert, put `Reverts #N` on its own line in the PR body, or `Reverts <sha>` for a
  commit with no PR number. Then push, an empty commit if nothing changed, because a body edit does
  not rerun the lint job. ci-wait's run is the one that counts when the base moved or the body
  changed after CI ran, and when the lint job skipped the step, as on a PR whose paths all sit in
  `paths-ignore`.

## Agent workflows

- Issues and PRDs live in GitHub Issues for `Sunnshiine/workout-app`. The workflow is
  `docs/agents/issue-tracker.md`, and the five triage labels are `docs/agents/triage-labels.md`.
- A UI prototype renders as HTML for a layout question, or ships to the phone through the
  `testflight` label for a question of feel. `docs/agents/prototyping.md` owns the decision.
