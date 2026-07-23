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

### Build economics — read this before your first xcodebuild

A full `xcodebuild test` pays a 9–13 min rebuild every time; the tests
themselves take 3–5 min. Eight full cycles burned a whole 120-min job on
PRD #497 slice 3. The loop below keeps the build out of the iteration:

- **Wait for the warm build.** The PRD workflow starts
  `xcodebuild build-for-testing` in the background before your session
  begins. `$RUNNER_TEMP/warm-build.log` absent means no warm build was
  started in this workflow — build yourself, no waiting. If the log exists,
  poll for `$RUNNER_TEMP/warm-build-exit-code` (up to ~15 min, e.g.
  `sleep 60` between checks). Marker contains `0`: the build products are
  ready — skip straight to `test-without-building`. Marker non-zero, or the
  cap expires: run `build-for-testing` yourself. Never run xcodebuild while
  the log exists but the marker is still absent — two builds on one
  DerivedData contend on locks.

  ```bash
  xcodebuild build-for-testing -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
    -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO
  ```

- **Iterate with `test-without-building`** — it reuses the built products and
  costs only the 3–5 min of test execution (less with a narrow filter):

  ```bash
  xcodebuild test-without-building -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
    -only-testing:WorkoutTrackerSnapshotTests \
    -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO
  ```

- **The invariant:** any edit under `WorkoutTracker/`, `Tests/`, or the
  xcodeproj invalidates the built products. `test-without-building` is legal
  **only if you have made zero edits since the last `build-for-testing`** —
  otherwise you are recording baselines from a stale binary, and they will
  assert green against that same stale binary while CI renders something
  else. After an edit: one `build-for-testing`, then iterate again.

- **Narrow the filter to what you changed.** `-only-testing` works at target
  (`WorkoutTrackerSnapshotTests`) and suite
  (`WorkoutTrackerSnapshotTests/SessionViewVisualTests`) granularity.
  **Method-level filters silently match 0 swift-testing `@Test` functions**
  (slice 3 lost two cycles to this) — never go deeper than the suite. To
  record a subset of one suite, flip the trait per-test instead:
  `@Test(.snapshots(record: .all))` on just the affected tests.

### The loop

1. **Record** the affected Visual Baselines on this runner's simulator. The
   recording switch is the trait, not an env var — `SNAPSHOT_TESTING_RECORD`
   does **not** work here (issue #471). Flip the affected suite's
   `@Suite(.snapshots(record: .never))` to `.snapshots(record: .all))` — or,
   for a subset, per-test `@Test(.snapshots(record: .all))` — in
   `Tests/Visual/*.swift`, build (invariant above), then run the affected
   suite via `test-without-building`.

   **Revert the trait to `.never` immediately after recording** — committing
   `.all` turns the gate off, and the `visual-tests` job now greps for it and
   fails the PR. A record run that crashes leaves the stale PNG silently in
   place (issue #479) — check the test log for the fixture actually
   rendering, and note that offscreen renders on iOS 27 resolve environment
   objects eagerly: a fixture missing an environment object crashes at
   render, so inject everything the view observes. Offscreen renders also
   **never apply async scrolling** (`scrollTo`, `scrollPosition` — the offset
   stays 0 no matter the delay): position scrollable content by layout
   (explicit initial content offset), not by async scroll.
2. **Look**: `Read` each recorded PNG under `Tests/Visual/__Snapshots__/` and
   compare it against the pick for that screen in `docs/design/greenhouse-picks/`
   and the DESIGN.md section the manifest names. **Do not run an assert-mode
   pass per iteration** — renders are byte-identical on this runner (issue
   #479), so the PNG a record run just wrote is bit-for-bit what assert mode
   would compare. Your eyes on the PNG are the iteration signal.
3. **Iterate** until the render matches the locked design (record → look →
   fix → rebuild → record), then run **one terminal full-target assert pass**
   — traits reverted to `.never`, `test-without-building`,
   `-only-testing:WorkoutTrackerSnapshotTests` — before committing. This
   single pass is mandatory and unnarrowed: it catches stale PNGs from
   crashed record runs (#479) and cross-cutting drift your narrow filter
   missed (a `Theme.swift` edit moves every suite). Then **commit the
   recorded baselines together with the code change**. Deleting a baseline
   without recording its replacement is never correct (that is exactly how
   PR #467 shipped wrong). New redesigned surfaces without a Visual test get
   one, with a baseline, as part of the change.

Known accepted flakes: the two old animated fixtures can mismatch
intermittently until slice 7 of PRD #497 replaces them (issue #482, owner-
accepted — `settingsView` flagged this way on slice 3). If a fixture you did
not touch mismatches once, re-run the terminal pass; if it is on the #482
list, do not chase it.

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
2. Drive the app through **each screen your change touches** (`snapshot_ui`
   for the accessibility hierarchy and elementRefs, then tap, swipe, gesture)
   and screenshot it. The first `snapshot_ui` right after launch can
   transiently fail with "No translation object returned for simulator" —
   wait a few seconds and retry (or use `wait_for_ui`); after that first
   success the tools are stable (issue #484 measured a 0-failure
   snapshot/tap loop on this runner). If instead you see "Failed to load
   essential private frameworks", the SimulatorKit bridge step in
   `.github/actions/setup-agent-mcp` did not run — say so in your report
   and fall back to screenshots of the screens you can reach by launch
   arguments; mechanism 1 covers every changed surface regardless.
3. Switch the simulator to dark appearance with
   `set_sim_appearance({ mode: "dark" })` (Bash fallback:
   `xcrun simctl ui <udid> appearance dark`) and screenshot the same screens
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
