# UI tests

Part of the AI-Generated Code Gate in [docs/TESTING.md](../TESTING.md), which defines the test
layers, names the UI target's two purposes, and holds the smoke selector commands. This file
defines UI Integration Smoke and the UI Interaction Suite.

UI XCUITest boundary:

- UI Integration Smoke is the real-control wiring layer. It proves launch state, navigation, accessibility
  lookup, hittability, route completion, and one representative end-to-end flow per critical app
  surface.
- The UI Interaction Suite covers higher-flake interaction mechanics such as keyboard focus,
  overscroll, long scrolling, hold gestures, and frame/visibility behavior. CI runs only its
  keyboard tests, `KeyboardLaneUITests`, and only on a pull request that touches what they reach
  (Keyboard lane, below). The rest stays opt-in (#662), so it runs locally before a change that
  needs it is ready.
- UI XCUITests may assert that a real user action reaches a visible result. Unit and component tests own
  the detailed state rules, permutations, string construction, persistence semantics, and business
  logic behind that result.
- UI XCUITests may include layout assertions only when the assertion protects functional accessibility:
  a control must remain tappable, readable, reachable, and not clipped out of usable bounds. Pixel
  polish, spacing, exact frame relationships, and broad appearance coverage belong to Visual
  Regression tests or component/presentation tests.
- Gesture-heavy surfaces should keep at most one representative UI gesture per critical path to
  prove the real SwiftUI attachment works. Component or unit tests own thresholds, timing, idle
  behavior, precommit releases, and state-machine edge cases.
- Settings and Developer Tools should have route smokes plus one representative critical
  confirmation path. Store, sync, reset, diagnostics, and pending-write rules belong to lower-level
  tests unless the app-layer wiring itself is the risk.
- UI cleanup issues must identify the replacement coverage owner before deleting or narrowing an
  XCTest. Either cite existing unit, component, or visual coverage, or add the missing
  lower-level coverage first.
- UI Integration Smoke lives in dedicated test classes inside the `WorkoutTrackerUITests` target,
  so a class-level selector runs it without the rest of the bundle.

UI-test frame assertions:

- Accessibility frames are hit targets, not visual bounds. Do not treat a native 44 pt hit target
  intersecting a compact visual element's layout frame as proof of a visual collision. For compact
  header controls such as the stage's session location button (`session-location-button`), prefer
  assertions that prove the control exists, is hittable, remains separated from real neighboring
  controls/cards, and opens the intended surface. Use Visual Regression tests or human review for
  actual visual-overlap questions.
- A frame assertion on the session stage launches animated and reads frames once they stop
  moving. With animations off, the active-set card rests 34 pt higher than an athlete sees it, so
  an assertion tuned there passes on a layout nobody sees. Keys and the Done button cover the
  screen from `min(keyboard top, Done midY)` down. The keyboard's `Toolbar` row above them draws
  nothing.

Keyboard lane:

CI's `visual-tests` job runs `KeyboardLaneUITests`, the weight keyboard tests, animated on every
pull request whose diff touches a file the tests reach. Those are the files the app and UI test
targets compile (`App/`, `Sources/WorkoutTracker/`, `WorkoutShared/`, `Tests/UI/`), the project
that defines those targets, and the lane's own wiring. `scripts/keyboard-lane-paths.sh` holds that
list, and the step's log names the paths that matched or says none did.
`scripts/ci-keyboard-lane.sh` is the step.

- Put a new test that opens the weight keyboard in `KeyboardLaneUITests`, so the lane runs it.
- Animated, the keyboard is still sliding out when a dismissing tap returns. Assert it is gone
  with `disappears(within:)`, not `exists`.
- Each `typeText` drops the keyboard below the window for most of a second, and the card rests at
  its idle place meanwhile. Read a frame through `restingFrame(of:keyboard:in:)`, which waits for
  the keyboard state as well as a still frame.
- Waits for something expected use `uiEventBudget`. A check that something does not happen keeps
  its own short window, since that window is the claim.
- A red `visual-tests` job is a Visual Baseline mismatch or a keyboard lane failure. Read which
  step failed before you follow the re-record loop. A failed lane uploads `KeyboardLane.xcresult`
  in `ui-test-results`.
- To measure the lane on the runner, run
  `gh workflow run ci.yml --ref <branch> -f keyboard-lane=true`.

Representative UI Integration Smoke scope:

- Launch the deterministic Current Session fixture, select RPE, log the first Set, and verify the
  next active Set advances.
- Move On from a deterministic completed or ready-to-advance Session, dismiss the Move On
  Celebration, and verify the next intended Session or Exercise appears.
- Open Block Overview, switch to a non-current Session, verify Make current / Go back controls, and
  return to the Current Session.
- Open Settings from a deterministic route and exercise one representative pending-write sign-out
  confirmation path.
- Open a Partially Uploaded Block, verify one Unavailable Session is inert, and verify one Available
  Session still opens.

Do not promote a broad chained journey into smoke. Split it into these short named flows first,
and leave keyboard focus, overscroll, long-session scrolling, hold gestures, exact frame movement,
and celebration visibility-ratio checks in the UI Interaction Suite.
