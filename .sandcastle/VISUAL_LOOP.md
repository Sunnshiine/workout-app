# The sighted inner loop (visual verification for UI-touching changes)

Contract for agents in the sandcastle pipeline (map #468, verdict #469): if your
change alters anything the user can see — `WorkoutTracker/Views/`, `Theme.swift`,
or any rendered surface — you must **look at what you built before committing**.
Two mandatory mechanisms, under one authority:

- The **CI Visual Regression gate** (ADR-0007; the `visual-tests` job in
  `ci.yml`) is the **sole pass/fail authority**. Your eyes iterate; the gate
  decides. Whenever what you see and what the gate says disagree, the gate wins.
- **Ground truth** is `docs/design/greenhouse-picks/` — `README.md` there maps
  screen → pick PNG → DESIGN.md section. Where a pick and DESIGN.md disagree,
  DESIGN.md wins. Never reopen a design decision; implement what is locked.

## Mechanism 1 — record-and-look (the mandatory floor)

When your change touches a surface covered by (or that should be covered by) a
Visual Regression test under `Tests/Visual/`:

1. **Record** the affected Visual Baselines on this runner's simulator. The
   recording switch is the suite trait, not an env var —
   `SNAPSHOT_TESTING_RECORD` does **not** work here (issue #471). Flip the
   affected suite's `@Suite(.snapshots(record: .never))` to
   `.snapshots(record: .all))` in `Tests/Visual/*.swift`, then run:

   ```bash
   xcodebuild test -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
     -only-testing:WorkoutTrackerSnapshotTests \
     -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO
   ```

   **Revert the trait to `.never` immediately after recording** — committing
   `.all` would turn the gate off. A record run that crashes leaves the stale
   PNG silently in place (issue #479) — check the test log for the fixture
   actually rendering, and note that offscreen renders on iOS 27 resolve
   environment objects eagerly: a fixture missing an environment object
   crashes at render, so inject everything the view observes.
2. **Look**: `Read` each recorded PNG under `Tests/Visual/__Snapshots__/` and
   compare it against the pick for that screen in `docs/design/greenhouse-picks/`
   and the DESIGN.md section the manifest names.
3. **Iterate** until the render matches the locked design, then **commit the
   recorded baselines together with the code change**. Deleting a baseline
   without recording its replacement is never correct (that is exactly how
   PR #467 shipped wrong). New redesigned surfaces without a Visual test get
   one, with a baseline, as part of the change.

You are running on the same runner image and OS pin as the `visual-tests` job,
so baselines you record here are canonical (issue #479 re-proved byte-identical
renders at exact precision across reboots on this pair).

## Mechanism 2 — XcodeBuildMCP eyes-on-app (mandatory for UI-touching issues)

The XcodeBuildMCP server is configured in `.mcp.json`, with session defaults
(project, scheme, simulator) in `.xcodebuildmcp/config.yaml`. In CI it runs
headless (`XCODEBUILDMCP_HEADLESS_LAUNCH=1`): the simulator boots via `simctl`
without a window and stays available for UI automation; only keyboard-shortcut
tools fail fast — do not use them.

1. Build and run the app on the simulator (`build_run_sim`), launching with
   fixture arguments `-UITEST_FIXTURE true -UITEST_SESSION true` so the app
   renders deterministic local fixtures, not live data. Pass build extra args
   `-skipPackagePluginValidation -skipMacroValidation` — SwiftLint's build
   plugin cannot be approved interactively in CI and fails the build without
   them (spike run 29705943290).
2. Drive the app through **each screen your change touches** (`describe_ui`,
   tap, swipe, gesture) and screenshot it. **Known limitation:** the current
   xcode-27 beta runner image ships without `SimulatorKit.framework`, so
   `describe_ui`/tap fail there — screenshot every changed screen you can
   reach (launch surface, launch-argument routes) and note the screens you
   could not; mechanism 1 covers every changed surface regardless. Resume
   the full drive-through when the tools work (issue #484 tracks the image).
3. Switch the simulator to dark appearance — no MCP tool does this; use Bash:
   `xcrun simctl ui <udid> appearance dark` — and screenshot the same screens
   again — the Greenhouse night edition is part of the locked design.
4. `Read` every screenshot and compare against the spec, DESIGN.md, and the
   greenhouse picks **before committing**. Fix what you see; re-drive.

If the MCP tools are not available in your session (server failed to load),
say so explicitly in your final report, complete mechanism 1 regardless, and
lean on the gate.

## What stays forbidden

Do not run `WorkoutTrackerUITests` (XCUITest) in this environment, and do not
write screenshot-tour XCUITests — that mechanism was explicitly rejected
(#469). The sighted loop above is the replacement.
