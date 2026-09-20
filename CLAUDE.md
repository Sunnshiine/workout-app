# CLAUDE.md

A mobile client for powerlifting athletes that surfaces and logs workouts from a
coach-managed Google Sheet. The Sheet is the single source of truth; the app is a
read-write client with a local cache (ADR-0001).

> Generic Swift conventions (style, testing, patterns, security) are loaded automatically
> from `~/.claude/rules/swift/` — they are intentionally not duplicated here.

## Build, Test & Run

Scheme is `WorkoutTracker` for all runs; default simulator is `iPhone 17 Pro` on iOS 27.0. Pin
`OS=27.0` in any `-destination`: a machine with more than one runtime holds several devices of
that name, and xcodebuild may pick the wrong one.

```bash
# Fast unit + component tests (no Secrets.xcconfig needed)
swift test

# One behavior, about a second: filter to the suite that covers it
swift test --filter ActiveSetFocusManagerTests

# Prove a concurrent test is not flaky: repeat it under full CPU load (docs/TESTING.md, Flaky Tests)
scripts/flake-hunt.sh --repetitions 1000 SyncCoordinatorTests

# Prove a pin catches what it claims: mutate a line, list the tests that fail it
scripts/mutate.sh --filter LoadSuggestionEngineTests Sources/WorkoutTracker/LoadSuggestionEngine.swift '/dropPercent/s/1 - /1 + /'

# Simulator suites: one build, then every requested suite from the xctestrun file
scripts/test-sim.sh unit            # hosted unit + component; not a superset of swift test (below)
scripts/test-sim.sh visual          # snapshot gate (ADR-0007)
scripts/test-sim.sh ui              # UI integration tests
scripts/test-sim.sh --no-build WorkoutTrackerUITests/WorkoutTrackerUISmokeTests/testCurrentSessionLogsFirstSetAndAdvancesActiveSet

# Build & run on the simulator
xcodebuild build -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0'
```

- Neither test run is a superset of the other. `swift test` compiles `Sources/` only, so it leaves
  out everything under `App/` and a green run does not prove the app compiles.
  `scripts/test-sim.sh unit` compiles the app but skips the macOS-only CLI suites
  (`WorkoutCLIBinaryTests`, `CLIFailureTests`). A change touching both sides needs both runs.
- Visual Baselines are recorded on the CI runner, not locally: renders differ across machines at
  exact precision. The recording recipe is in `docs/TESTING.md`; the rule is ADR-0007.
- `scripts/test-sim.sh` is the documented way to run simulator tests. A bare `xcodebuild test`
  fails on a fresh machine ("Validate plug-in SwiftLintBuildToolPlugin") unless it also passes
  `-skipPackagePluginValidation -skipMacroValidation`, and after any failing run it spawns
  `simctl diagnose` with a 600 s timeout that intermittently hangs; the script passes
  `-collect-test-diagnostics never` and runs from the xctestrun so the project and package
  graph load once. The `.xcresult` bundle and snapshot diffs are unaffected.
- The `WorkoutTracker` scheme launches with `-UITEST_FIXTURE true` and
  `-UITEST_SESSION true` — it runs against deterministic local fixtures, **not**
  the live Google Sheet. To run against live data, use the `Copy of WorkoutTracker` scheme (`-UITEST_FIXTURE false`).
- To drive the app like a user and capture proof (screenshots plus the accessibility tree), use
  the project `verify` skill: `.claude/skills/verify/SKILL.md` owns launch, doctor, drive,
  evidence, and cleanup, and `.claude/skills/verify/features/` maps every user-facing feature
  to a recipe. Read the feature file before driving.
- To put several images in front of an agent in one read, tile them:
  `scripts/contact-sheet.swift OUT.png IMAGE...` (12 per sheet, 2000 px long edge, cells numbered
  and labelled by file name, no options). `verify.sh sheet` uses it for a run's shots.
- Prefer XcodeBuildMCP for build/run/test on the simulator. If using XcodeBuildMCP,
  use the installed XcodeBuildMCP skill before calling XcodeBuildMCP tools. The pin in
  `.mcp.json` must stay at 2.7.0 or later: older builds fail on Xcode 27 with
  "SimulatorKit.framework ... does not exist" for every accessibility call.
- If XcodeBuildMCP accessibility snapshots return an empty AXApplication, reboot
  the simulator before diagnosing app code.
- For target-specific UI gates, prefer raw `xcodebuild ... -only-testing:WorkoutTrackerUITests`
  or verify the output actually ran `WorkoutTrackerUITests`.

## Headless CLI (for agents)

`workout` drives the real application (same stores as the app) against a local workbook and
prints JSON. No simulator, no Google credentials, milliseconds per call. Full reference:
`Sources/WorkoutCLI/README.md`; the decision: `docs/adr/0015-headless-application-boundary.md`.

```bash
swift build --product workout && export PATH="$PWD/.build/debug:$PATH"
export WORKOUT_HOME=$(mktemp -d)
workout init --scenario fresh-block   # seed + select + sync
workout session                       # addresses on every Exercise and Set (w1d1.e0.s0)
workout log w1d1.e0.s0 185x5@8        # WorkoutStore.log; no auto-flush
workout flush && workout sheet --cell K15   # "185x5@8" landed in the workbook
workout sync && workout session w1d1  # the Set reads back as logged through the parser
```

Errors are JSON on stderr with exit 1 (domain), 3 (environment), 4 (conflict).

## Change risk gate (CRAP)

Every production function in the headless scope carries a CRAP score (`cc^2 * (1 - coverage)^3 + cc`);
the target is 6 or lower and `tools/crap/baseline.tsv` lists the functions still above it, each with
the reason it is held. The decision and the scope are in `docs/adr/0016-crap-change-risk-gate.md`;
the counting rules are in `tools/crap/README.md`.

```bash
scripts/crap.sh measure --top 30   # worst functions by score, with cc and coverage
scripts/crap.sh gate               # the CI check: new or worsened violations fail, stale baseline rows fail
scripts/crap.sh baseline           # shrink the baseline after an improvement
jq '.functions[] | select(.file | contains("Stores/"))' .build/crap/report.json   # full report
```

The measured scope is `Sources/`. `App/`, `WorkoutShared/` and `WorkoutWidgets/` are outside
`swift test` and therefore unmeasured. Lower a score with a better design or a stronger test; never
by weakening a test or splitting a function into pieces with no name.

## Linting & Formatting

- **SwiftLint** has two runners over one `.swiftlint.yml`. The `SwiftLintPlugins` build tool plugin
  (wired through the Xcode project, not `Package.swift`) lints the app target on every Xcode build.
  `scripts/lint.sh` lints every tree the config's `included:` names, with no build, and the `lint`
  CI job runs it. Use it before you push:

  ```bash
  scripts/lint.sh          # what CI runs; --strict, so a warning fails too
  scripts/lint.sh --fix    # autocorrect what SwiftLint can, then lint
  ```

  The script fetches the same SwiftLint binary the plugin runs, at the version
  `WorkoutTracker.xcodeproj/.../Package.resolved` pins, so the two runners cannot disagree about
  what a violation is. Re-pin by bumping SwiftLintPlugins in Xcode and committing `Package.resolved`.
- `Tests/.swiftlint.yml` switches off three rules a test body reads better without, with the reason
  per rule. Exceptions are per rule and argued; a blanket exclusion of a tree is not one.
- **swift-format** is installed via Homebrew. Config: `.swift-format`. Run manually: `swift-format -i -r App/ Sources/ Tests/`
- Do not run `swiftlint --fix` in build phases — run it manually when needed.

## Git Worktrees

`Secrets.xcconfig` is git-ignored but required for Xcode app-target builds. New
git worktrees should receive it automatically from the tracked post-checkout
hook once the bootstrap is installed:

```bash
scripts/install-worktree-bootstrap.sh --source /path/to/private/Secrets.xcconfig
```

The installer sets `core.hooksPath=.githooks`, records the trusted source when
`--source` is provided, and backfills existing worktrees. The bootstrap source
order is: `SECRETS_XCCONFIG_SOURCE`, `git config workout.secretsXcconfigSource`,
the `main` worktree's `Secrets.xcconfig`, then `Secrets.xcconfig.template` as a
build-only fallback. `swift test` does not require it; only Xcode app-target
builds do.

XcodeBuildMCP session defaults point at the main project path and do not apply inside a worktree. Pass `-project <worktree-path>/WorkoutTracker.xcodeproj` explicitly when calling xcodebuild from a worktree.

Merged worktrees pile up and cost gigabytes of `.build`. `scripts/prune-merged-worktrees.sh` resolves every worktree's branch through its PR state and lists the ones whose PR has merged or closed; it dry-runs by default and removes only under `--apply`, never touching the primary checkout or a worktree holding uncommitted or unpushed work.

## Landing a PR

```bash
scripts/ci-wait.sh 123        # wait for CI on the PR's head commit; exits 0 only on success
gh pr merge 123 --squash      # GitHub deletes the remote branch itself
scripts/ci-wait.sh            # wait for the merge's own run on main
```

Leave out `--delete-branch`: it adds nothing but a local side effect, switching whichever worktree
holds the branch onto `main`.

## Architecture

A navigation map; see `CONTEXT.md` for the domain glossary and `docs/adr/` for decisions.

The directory a file sits in decides which builds compile it (ADR-0017).

```text
App/                            iOS app only; not in the SwiftPM package
├── WorkoutTrackerApp.swift     App entry point (@main)
├── GoogleAuth.swift            Google Sheets sign-in (needs a UIKit presentation anchor)
├── Views/                      SwiftUI views
├── LiveActivity/               Live Activity controller and its production adapter
└── Assets.xcassets, Fonts/, AppIcon.icon, Info.plist, LaunchScreen.storyboard

Sources/WorkoutTracker/         SwiftPM library, also compiled into the app target
├── Models/                     Domain types and the persisted schema (Block, Week, Session, Exercise, Set …)
├── Parsing/                    Sheet → domain interpretation (layout interpreter)
├── Sheets/                     Google Sheets client
├── Stores/                     Local cache, sync coordination & persisted state
├── Session/                    The live session (coordinator, active-set focus, Supersets, Stage, Set Card)
├── Rest/                       Rest timer, notification, haptics, pill, and the rest Live Activity content
├── Progress/                   Where the athlete is in the Block (Current Session, grid, Move On, Open Exercises)
├── ExerciseHistory/            Last Performed lookup and extraction, Movement matching, the history sheet
├── Onboarding/                 App entry destination, connect screen, Sheet picker
├── Application/                WorkoutApplication (composition root + public facade), addresses, snapshots
├── HapticPlayer.swift          Haptic playback (rest cues and the Move On celebration)
├── LoadSuggestionEngine.swift  Load Suggestion calculations
├── Theme.swift                 Liquid Glass design system (ADR-0004)
└── Fixtures/                   UI-test fixture data (-UITEST_FIXTURE) and WorkbookScenario seeds

Sources/WorkoutCLI/             The `workout` executable (ADR-0015)
Tests/  →  Unit/ · Component/ · UI/ · Support/
```

`App/`, `Sources/WorkoutTracker/`, `WorkoutShared/`, and `WorkoutWidgets/` are Xcode buildable
folders, like the folders under `Tests/`. A Swift file added under one compiles into its target with
no project edit. `WorkoutShared/` builds into both the app and the widget. Xcode also copies any
other file in these folders into the bundle, including a Markdown note. To keep a file out of the
bundle, add a membership exception in the project, as each `Info.plist` has.

The app target compiles `App/` and `Sources/WorkoutTracker/`; `swift test` compiles
`Sources/WorkoutTracker/` alone. So a file needs iOS-only API, or it needs headless test coverage,
and where you put it is that choice. `Sources/WorkoutCLI/` is in neither the app nor the widget.

## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues for `Sunnshiine/workout-app`. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default five-label triage vocabulary. See `docs/agents/triage-labels.md`.

### Sandcastle agent pipeline

Label-driven autonomous implementation via GitHub Actions: `agent:to-issues` slices a PRD into sub-issues, `agent:implement` implements issues/PRDs/PR feedback, `agent:review` reviews PRs. Prompts live in `.sandcastle/`, workflows in `.github/workflows/agent-*.yml`. See `docs/agents/sandcastle.md`.

### Domain docs

This is a single-context repo: read root `CONTEXT.md` for domain language and root `docs/adr/` for decisions. For product or UI work, also read `PRODUCT.md` and `DESIGN.md`. See `docs/agents/domain.md`.

### Prototyping

The review surface is an iPhone. A UI prototype from the `/prototype` skill has two render targets: an **HTML render** for questions a screenshot can settle (layout, hierarchy), or a **device build** — a throwaway PR shipped to the phone via the `testflight` label — for questions of feel (materials, motion, gestures). Pick the target per `docs/agents/prototyping.md` before building; it owns the decision test and both flows.
