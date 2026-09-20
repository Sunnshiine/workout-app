# AGENTS.md

WorkoutTracker is an iOS client for powerlifting athletes. It surfaces and logs the workouts a
coach manages in a Google Sheet. The Sheet is the single source of truth and the app is a
read-write client with a local cache (ADR-0001). `CLAUDE.md` is a symlink to this file.

## Sources of truth

Each of these wins over anything written here. Read the one that governs the work before starting.

- `CONTEXT.md` names every domain term and the synonyms to avoid. Use its words in code, tests,
  and issues.
- `docs/adr/` records decisions. Read the ADRs for the area you change. If your change contradicts
  one, say so in the PR instead of overriding it.
- `PRODUCT.md` and `DESIGN.md` govern product and UI work. Read them first for either.
- `CODING_STANDARDS.md` is the review standard. Its rules are the ones that cost this repo a
  shipped bug and take judgment a lint does not have. Read it before changing a store, a
  coordinator, a View's logic, or a test, and apply it at review.
- `.swift-format` and `.swiftlint.yml` own formatting and every mechanical rule.
- `docs/TESTING.md` owns the change-risk gate and flake hunting. `tools/crap/README.md` and
  ADR-0016 own the gate's counting rules.
- `Sources/WorkoutCLI/README.md` owns the `workout` CLI. ADR-0015 records the boundary it runs on.
- `.agents/skills/verify/SKILL.md` drives the app on the simulator and captures proof. Read the
  matching file under `.agents/skills/verify/features/` before driving.

## Repository map

The directory a file sits in decides which builds compile it (ADR-0017). These entries are stable.
The folders inside them move, so read the tree instead of a copy of it.

```text
App/                     The iOS app alone: entry point, Views, Live Activity controller, Google
                         sign-in, assets. Outside the package, so swift test never sees it.
Sources/WorkoutTracker/  The library, compiled into the app, the CLI, and swift test: the domain
                         model, Sheet parsing, sync and stores, session and progress logic, the
                         fixtures, and WorkoutApplication.
Sources/WorkoutCLI/      The workout executable. In neither the app nor the widget.
WorkoutShared/           Live Activity attributes, compiled into the app and the widget.
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

- Code that needs UIKit or another iOS-only API belongs in `App/`. Everything else, including
  every guard, calculation, or branch that decides behaviour, belongs in `Sources/WorkoutTracker/`,
  where `swift test` and the CLI can reach it.
- `WorkoutApplication` is the composition root and the public facade. The app and the CLI both
  build on it (ADR-0015).
- The Sheet is written only through `SyncCoordinator` and its pending-write queue (ADR-0006).

## Commands

```bash
swift test                                        # unit + component; no Secrets.xcconfig needed
swift test --filter ActiveSetFocusManagerTests    # one file's tests, about a second
scripts/lint.sh                                   # what CI runs, --strict; --fix autocorrects first
swift-format -i -r App/ Sources/ Tests/           # format
scripts/crap.sh gate                              # the change-risk gate CI runs (ADR-0016)
scripts/test-sim.sh unit                          # simulator suites from one build: unit | visual | ui | all
scripts/test-sim.sh --no-build WorkoutTrackerUITests/WorkoutTrackerUISmokeTests/testCurrentSessionLogsFirstSetAndAdvancesActiveSet
xcodebuild build -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0'
scripts/flake-hunt.sh --repetitions 1000 SyncCoordinatorTests   # repeat a concurrent test under load
scripts/mutate.sh --filter LoadSuggestionEngineTests Sources/WorkoutTracker/LoadSuggestionEngine.swift '/dropPercent/s/1 - /1 + /'   # which tests kill a mutant
```

The headless CLI drives the real stores against a local workbook and prints JSON, in milliseconds,
with no simulator and no Google credentials:

```bash
swift build --product workout && export PATH="$PWD/.build/debug:$PATH"
export WORKOUT_HOME=$(mktemp -d) && workout init --scenario fresh-block
workout log w1d1.e0.s0 185x5@8 && workout flush && workout sheet --cell K15   # "185x5@8" landed
```

## Verification

Run `scripts/lint.sh` and `swift test` before finishing. On every PR, CI runs those, the CRAP
gate, the simulator-hosted unit and component suite, and the visual gate. A PR whose changed paths
all sit in `ci.yml`'s `paths-ignore` (Markdown, `docs/`, agent files, and more) starts no run.

- Neither test run is a superset of the other. `swift test` compiles `Sources/` alone, so a green
  run does not prove the app compiles. `scripts/test-sim.sh unit` compiles the app and skips the
  macOS-only CLI suites (`WorkoutCLIBinaryTests`, `CLIFailureTests`). Before pushing a diff that
  touches `App/`, run the simulator suite as well.
- Run simulator suites through `scripts/test-sim.sh`. A bare `xcodebuild test` fails plug-in
  validation on a fresh machine and can hang collecting diagnostics after a failure.
- Pin `OS=27.0` in every `-destination`. A machine with two runtimes holds two devices named
  iPhone 17 Pro, and xcodebuild may pick the wrong one.
- Concurrent UI-test sessions must not share a simulator. Give each its own UDID
  (`-destination 'platform=iOS Simulator,id=<UDID>'`) and its own `-derivedDataPath` and
  `-clonedSourcePackagesDirPath`.
- The `WorkoutTracker` scheme launches against local fixtures (`-UITEST_FIXTURE true`), never the
  live Sheet. `Copy of WorkoutTracker` runs live.
- Visual Baselines are recorded on the CI runner, not locally, because renders differ across
  machines (ADR-0007; the recipe is in `docs/TESTING.md`).

## Worktrees and landing

- `Secrets.xcconfig` is git-ignored and needed only for Xcode app builds; `swift test` runs without
  it. `scripts/install-worktree-bootstrap.sh --source <path>` installs the post-checkout hook that
  copies it into every new worktree. In a worktree the hook did not run in, run
  `sh .githooks/post-checkout` once.
- XcodeBuildMCP session defaults point at the primary checkout. From a worktree, pass
  `-project <worktree>/WorkoutTracker.xcodeproj` explicitly. The `.mcp.json` pin stays at 2.7.0 or
  later, because older builds fail every accessibility call on Xcode 27.
- Land with `scripts/ci-wait.sh N` and then `gh pr merge N --squash`. Leave out `--delete-branch`.
  GitHub deletes the remote branch itself, and the flag switches whichever worktree holds the
  branch onto `main`. `scripts/prune-merged-worktrees.sh` lists worktrees whose PR has merged or
  closed and removes them only under `--apply`.

## Agent workflows

- Issues and PRDs live in GitHub Issues for `Sunnshiine/workout-app`. The workflow is
  `docs/agents/issue-tracker.md`, and the five triage labels are `docs/agents/triage-labels.md`.
- Sandcastle runs label-driven implementation and review in GitHub Actions. Prompts are in
  `.sandcastle/`, workflows in `.github/workflows/agent-*.yml`, and the map is
  `docs/agents/sandcastle.md`.
- A UI prototype renders as HTML for a layout question, or ships to the phone through the
  `testflight` label for a question of feel. `docs/agents/prototyping.md` owns the decision.
