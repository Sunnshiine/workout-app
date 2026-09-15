# CLAUDE.md

A mobile client for powerlifting athletes that surfaces and logs workouts from a
coach-managed Google Sheet. The Sheet is the single source of truth; the app is a
read-write client with a local cache (ADR-0001).

> Generic Swift conventions (style, testing, patterns, security) are loaded automatically
> from `~/.claude/rules/swift/` — they are intentionally not duplicated here.

## Build, Test & Run

Scheme is `WorkoutTracker` for all runs; default simulator is `iPhone 17 Pro`.

```bash
# Fast unit + component tests (no Secrets.xcconfig needed)
swift test

# One behavior, about a second: filter to the suite that covers it
swift test --filter ActiveSetFocusManagerTests

# Simulator suites: one build, then every requested suite from the xctestrun file
scripts/test-sim.sh unit            # hosted unit + component (adds the UIKit-only tests)
scripts/test-sim.sh visual          # snapshot gate (ADR-0007)
scripts/test-sim.sh ui              # UI integration tests
scripts/test-sim.sh --no-build WorkoutTrackerUITests/WorkoutTrackerUISmokeTests/testCurrentSessionLogsFirstSetAndAdvancesActiveSet

# Build & run on the simulator
xcodebuild build -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

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
`WorkoutCLI/README.md`; the decision: `docs/adr/0015-headless-application-boundary.md`.

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
the target is 12 or lower and `tools/crap/baseline.tsv` lists the functions still above it. The
decision and the scope are in `docs/adr/0016-crap-change-risk-gate.md`; the counting rules are in
`tools/crap/README.md`.

```bash
scripts/crap.sh measure --top 30   # worst functions by score, with cc and coverage
scripts/crap.sh gate               # the CI check: new or worsened violations fail, stale baseline rows fail
scripts/crap.sh baseline           # shrink the baseline after an improvement
jq '.functions[] | select(.file | contains("Stores/"))' .build/crap/report.json   # full report
```

`Views/`, `LiveActivity/`, `GoogleAuth.swift`, `WorkoutTrackerApp.swift`, `WorkoutShared/`, and
`WorkoutWidgets/` are outside `swift test` and therefore unmeasured. Lower a score with a better
design or a stronger test; never by weakening a test or splitting a function into pieces with no name.

## Linting & Formatting

- **SwiftLint** runs automatically via the `SwiftLintPlugins` build tool plugin (wired through the Xcode project, not `Package.swift`). Config: `.swiftlint.yml`.
- **swift-format** is installed via Homebrew. Config: `.swift-format`. Run manually: `swift-format -i -r WorkoutTracker/ WorkoutCLI/ Tests/`
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

## Architecture

A navigation map; see `CONTEXT.md` for the domain glossary and `docs/adr/` for decisions.

```text
WorkoutTracker/
├── WorkoutTrackerApp.swift     App entry point (@main)
├── Models/                     Domain types (Block, Week, Session, Exercise, Set …)
├── Parsing/                    Sheet → domain interpretation (layout interpreter)
├── Sheets/                     Google Sheets client + auth (GoogleAuth.swift)
├── Stores/                     Local cache, sync coordination & persisted state
├── Progress/                   Session/Week progression (Current Session, Move On, Open Exercises, Supersets)
├── LoadSuggestionEngine.swift  Load Suggestion calculations
├── Theme.swift                 Liquid Glass design system (ADR-0004)
├── App/                        WorkoutApplication (composition root + public facade), addresses, snapshots
├── Views/                      SwiftUI views (excluded from the SPM library target)
└── Fixtures/                   UI-test fixture data (-UITEST_FIXTURE) and WorkbookScenario seeds

WorkoutCLI/                     The `workout` executable (ADR-0015)
Tests/  →  Unit/ · Component/ · UI/ · Support/
```

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
