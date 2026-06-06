# UI Integration Smoke Ralph Gate Spec

## Goal

Reshape `WorkoutTrackerUITests` from one broad all-purpose UI target into two explicit XCUITest
roles: a small UI Integration Smoke layer that Ralph may run, and a UI Interaction Suite that stays
manual, nightly, pre-release, or otherwise outside Ralph's autonomous loop.

The goal is confidence that release-critical app wiring still works without letting unreliable
keyboard, gesture, scroll, frame, or broad end-to-end journeys create false alarms in Ralph.

## Background

The testing policy already defines the app's layered confidence model in
[docs/TESTING.md](../TESTING.md): unit and component tests own state rules, Visual Regression tests
own pixels, and UI XCUITests prove critical real-control wiring. [ADR 0007](../adr/0007-visual-regression-testing.md)
separates deterministic visual coverage from UI interaction coverage, so UI XCUITests should not be
used as a substitute for visual baselines.

The current UI target has useful coverage but mixes roles. `Tests/UI/WorkoutTrackerUITests.swift`
contains a broad `testFixtureDrivenCoreSessionFlow`, keyboard/focus checks, overscroll Settings
reveal, Settings and Developer Tools route checks, an Open Exercise makeup flow, long-session scroll
checks, and hold-to-skip. `Tests/UI/PartiallyUploadedBlockUITests.swift` covers Partially Uploaded
Block behavior. `project.yml` wires all of `Tests/UI` into one `WorkoutTrackerUITests` target.

Ralph currently still has full-target UI wiring in its orchestration surfaces:
[Ralph README](../../ralph/README.md), `ralph/prompts/ui-verify.md`, and
`ralph/orchestrator/loop.py` reference `-only-testing:WorkoutTrackerUITests`. That command selects
the whole UI bundle, which conflicts with the accepted policy that Ralph must not run the full UI
target or the higher-flake interaction suite.

## Decisions

- Decision: Keep XCUITest as the native iOS UI automation tool.
  - Source: Testing discussion, 2026-06-06.
  - Consequence: No Maestro or Appium migration is in scope for this work.

- Decision: Split UI XCUITest ownership into UI Integration Smoke and UI Interaction Suite.
  - Source: [docs/TESTING.md](../TESTING.md).
  - Consequence: Ralph may run smoke only; interaction-heavy tests are explicit non-Ralph coverage.

- Decision: UI Integration Smoke remains inside the existing `WorkoutTrackerUITests` target.
  - Source: Testing discussion, 2026-06-06.
  - Consequence: No new Xcode target or test plan is required for the first migration.

- Decision: Ralph can run smoke only through class-level `-only-testing` selectors.
  - Source: [docs/TESTING.md](../TESTING.md).
  - Consequence: `-only-testing:WorkoutTrackerUITests` is not an acceptable Ralph command because it
    selects the full UI bundle.

- Decision: The existing broad core-session journey must be split before it is Ralph-run smoke.
  - Source: Testing discussion, 2026-06-06 and [docs/TESTING.md](../TESTING.md).
  - Consequence: The smoke suite is a set of short named flows, not one long chained end-to-end test.

- Decision: TestFlight is out of scope for this migration.
  - Source: User direction, 2026-06-06.
  - Consequence: Release-candidate beta feedback is not part of this spec's acceptance criteria.

## Scope

### In

- UI Integration Smoke naming and selector contracts.
- UI Interaction Suite exclusion from Ralph.
- Migration from broad full-target UI execution to class-level smoke selectors.
- Ralph gate, prompt, README, and tests needed to enforce smoke-only execution.
- Preservation of `Tests/UI/**` edit-authority checks.
- Representative smoke flow boundaries.

### Out

- Adopting Maestro, Appium, or another UI automation framework.
- Creating a new Xcode target or Xcode test plan for smoke.
- Changing product behavior.
- Replacing Visual Regression tests or Visual Baselines.
- Running TestFlight or designing beta feedback flows.
- Making every current UI test reliable enough for Ralph.

## Current Architecture

`Tests/UI` is compiled into one Xcode UI-test target named `WorkoutTrackerUITests`. The `WorkoutTracker`
scheme includes that target, and the Ralph gate currently uses an Xcode command that selects the
whole UI bundle.

Current UI test files:

- `Tests/UI/WorkoutTrackerUITests.swift`: core session journey, keyboard/focus, non-current Session
  controls, Developer Tools route, Open Exercise makeup, Settings reveal/sign-out, appearance picker,
  long-session scroll, and hold-to-skip.
- `Tests/UI/PartiallyUploadedBlockUITests.swift`: Partially Uploaded Block grid and terminal Move On.
- `Tests/UI/WorkoutUITestSupport.swift`: shared launch fixtures and wait helpers.

Current Ralph integration points:

- `ralph/orchestrator/loop.py`: defines `GATE_UI_INTEGRATION` command with
  `-only-testing:WorkoutTrackerUITests`.
- `ralph/prompts/ui-verify.md`: tells the UI verification phase to run the whole UI target.
- `ralph/README.md`: documents raw UI-test probes and app gates against the whole UI target.
- `ralph/orchestrator/authority.py`: enforces `Tests/UI/**` edit authority mechanically.

## Target Architecture

The existing `WorkoutTrackerUITests` target remains the compilation boundary. Test classes inside
that target define the execution boundary.

UI Integration Smoke is represented by dedicated classes whose names end in `UISmokeTests`.
Ralph's UI gate invokes only those classes with class-level `-only-testing` selectors. A Ralph smoke
command may include multiple selectors, but none may select the target bundle by itself.

The UI Interaction Suite remains in the same target unless a later migration creates a separate
target or test plan. It covers keyboard focus, overscroll, long-session scrolling, hold gestures,
exact frame movement, and celebration visibility-ratio checks. Ralph must not select these classes.

The Ralph authority gate remains independent from execution selection. Ralph still blocks
unauthorized `Tests/UI/**` changes unless the issue body grants `UI integration test edits:
authorized`, and UI verification/repair phases still obey their edit restrictions. The change is
what Ralph runs after implementation: smoke selectors, not the full UI bundle.

## Contracts

### UI Integration Smoke class selector [ADDED]

Smoke tests are exposed through class names inside the existing UI target:

```text
WorkoutTrackerUITests/<SmokeClassName>
```

Rules:

- Smoke class names end in `UISmokeTests`.
- Ralph may select smoke classes with `-only-testing:WorkoutTrackerUITests/<SmokeClassName>`.
- Ralph may select more than one smoke class in the same command.
- Ralph must not use `-only-testing:WorkoutTrackerUITests` without a class suffix.

### UI Interaction Suite exclusion [ADDED]

Interaction tests are tests that intentionally exercise higher-flake mechanics:

- keyboard focus and dismissal
- overscroll and pull gestures
- long-session scrolling
- hold gestures
- exact frame movement
- visibility-ratio assertions
- broad chained end-to-end journeys

Ralph must not include interaction classes in its smoke selectors.

### Ralph UI gate command [CHANGED]

The UI gate changes from full-target execution to smoke-class execution.

Removed shape:

```text
xcodebuild ... test -only-testing:WorkoutTrackerUITests
```

Target shape:

```text
xcodebuild ... test \
  -only-testing:WorkoutTrackerUITests/WorkoutTrackerUISmokeTests \
  -only-testing:WorkoutTrackerUITests/PartiallyUploadedBlockUISmokeTests
```

The exact class set may change as the smoke suite evolves, but every selected class must be a
dedicated smoke class.

### Broad core-session journey [REMOVED]

The Ralph-run smoke surface must not contain a single broad chained journey that validates multiple
features by navigating through the UI as setup. The existing broad journey is replaced by short
named flows before any equivalent coverage is included in Ralph.

### Representative smoke flows [ADDED]

The initial UI Integration Smoke suite covers these flows:

- Current Session fixture: select RPE, log the first Set, verify the next active Set advances.
- Move On: advance from a deterministic ready-to-advance Session, dismiss the celebration, verify
  the next intended Session or Exercise appears.
- Current Session override: open Block Overview, switch to a non-current Session, verify Make
  Current / Go Back controls, and return to the Current Session.
- Settings pending-write confirmation: open Settings from a deterministic route and exercise one
  representative pending-write sign-out confirmation path.
- Partially Uploaded Block: verify one Unavailable Session is inert and one Available Session opens.

### UI test edit authority [CHANGED]

Execution selection changes, but edit authority remains body-gated:

- `Tests/UI/**` edits still require the issue body line `UI integration test edits: authorized`.
- UI-test target wiring changes still require the existing mechanical authority path.
- The authority gate should refer to UI XCUITest edits rather than implying every UI test is
  Ralph-run smoke.

## Migration Plan

### Phase 1: Capture Policy and Naming

- Change: Keep [docs/TESTING.md](../TESTING.md) as the policy source for UI Integration Smoke, UI
  Interaction Suite, class-level selectors, and Ralph's full-target exclusion.
- Compatibility: Existing tests and Ralph commands continue to run until the mechanical migration
  lands.
- Acceptance criteria: The policy states that Ralph may run only mechanically isolated smoke
  classes and must not run the full UI target or the interaction suite.

### Phase 2: Isolate Smoke Classes

- Change: Split the current UI coverage into dedicated `UISmokeTests` classes and non-smoke
  interaction classes. Replace the broad core-session journey with short smoke flows.
- Compatibility: The existing `WorkoutTrackerUITests` target remains the only UI-test target.
- Acceptance criteria: The smoke classes cover the representative smoke flows, and interaction
  mechanics are not present in any class Ralph will select.

### Phase 3: Repoint Ralph to Smoke Selectors

- Change: Update Ralph's UI gate, UI verification prompt, README command examples, and Ralph unit
  tests so the orchestrator runs only class-level smoke selectors.
- Compatibility: `Tests/UI/**` edit authority checks remain active and continue to block
  unauthorized UI-test edits.
- Acceptance criteria: No Ralph command or prompt asks agents to run `-only-testing:WorkoutTrackerUITests`
  without a smoke class suffix.

### Phase 4: Interaction Suite Command Surface

- Change: Document a human/manual or non-Ralph command for running the UI Interaction Suite when
  higher-flake interaction confidence is required.
- Compatibility: Interaction tests remain available locally and in any explicit external gate.
- Acceptance criteria: The interaction command is clearly separate from Ralph and does not appear in
  Ralph's autonomous gate path.

## Deletion Criteria

- Delete or replace `testFixtureDrivenCoreSessionFlow` once its useful coverage is represented by
  short smoke flows and lower-level tests.
- Remove full-target UI command examples from Ralph docs once class-level smoke selectors exist.
- Remove any Ralph tests that assert `GATE_UI_INTEGRATION` selects the full UI target.
- Remove any prompt wording that tells a Ralph phase to run all of `WorkoutTrackerUITests`.

## Acceptance Criteria

- [ ] UI Integration Smoke classes exist inside the existing `WorkoutTrackerUITests` target and use
  class names ending in `UISmokeTests`.
- [ ] Ralph's UI gate command selects only smoke classes with class-level `-only-testing` arguments.
- [ ] Ralph never uses `-only-testing:WorkoutTrackerUITests` without a class suffix.
- [ ] Interaction-heavy tests remain runnable outside Ralph and are not selected by Ralph.
- [ ] `Tests/UI/**` edit authority remains mechanically enforced.
- [ ] The broad core-session journey is split or removed before equivalent coverage is included in
  Ralph smoke.
- [ ] Ralph docs and prompts describe smoke-only UI execution.

## Testing Strategy

Use Python tests around Ralph gate specs and prompt text to prove the orchestrator cannot select the
whole UI target. Use focused Xcode UI runs for each smoke class to prove the class selectors execute
the intended tests. Keep interaction-suite verification separate and manual/non-Ralph unless a later
spec changes that boundary.

Expected verification surfaces:

- Ralph unit tests for `_gate_specs`, `_gate_name_for_command`, and prompt text.
- Xcode UI run using the smoke class selectors.
- Existing non-UI gates: `swift test`, Xcode unit/component tests, Visual Regression tests when
  relevant, and `swiftlint lint --quiet`.

## Open Questions

- None.
