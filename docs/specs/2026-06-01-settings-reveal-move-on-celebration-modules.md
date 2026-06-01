# Settings Reveal and Move On Celebration Modules Spec

## Goal

Deepen two currently shallow Session modules before the implementation issues proceed:

- Current Session Settings reveal: make the hidden Settings affordance explicit as a small Session-specific
  state module instead of a boolean tied directly to scroll offset.
- Move On Celebration presentation: make the celebration's meaning explicit in pure presentation data so the
  SwiftUI view can stay focused on rendering, animation, haptics, and dismissal.

This spec is implementation-neutral planning for #140, #141, #142, #143, and #144. It references parent
PRDs #137 and #138 as source context by issue number and title only; those PRD bodies are not copied here.

## Background

The athlete uses the app mid-Session to read prescribed Sets, log Set Logs, and choose Move On when leaving a
Current Session. The product direction in [PRODUCT.md](../../PRODUCT.md) is warm, focused, and trustworthy:
Settings are a recovery surface, not a primary Session control, and celebration is earned and occasional.

The current Session HUD and Move On Celebration already exist, but both modules are too shallow for the next
set of issues:

- `SessionControlsVisibility` in `WorkoutTracker/Progress/ActiveSetPresentation.swift` is a two-state value
  with one reveal threshold and one dismiss threshold. It cannot describe hidden, previewing, pinned, timeout,
  Current Session-only, release-to-commit, explicit dismissal, or reduced-motion outcomes.
- `SessionView` owns the scroll offset hook, Settings sheet presentation, non-current Session override controls,
  Move On request, and overlay presentation. That is the right owner for Session orchestration, but it should not
  encode the reveal state machine inline.
- `SessionProgressHeader` currently receives `showsSessionControls: Bool` and conditionally renders one
  Settings button. The header renders the HUD, but it does not own whether a reveal is legal.
- `SmartValuePills` and `LoggedSetReviewCard` own private Weight/Reps keyboard focus state. Inert-space
  all-clear behavior must not turn their private editing state into parent-owned form state.
- `MoveOnCelebrationPresentation` already owns Week, title/subline, stats, quote, accessibility, and haptic
  style, while `MoveOnCelebrationView` owns the full-screen overlay, tap dismissal, ripple/checkmark visuals,
  and haptics. The next issues need the presentation to carry the new Glass Bloom meaning without making the
  view responsible for computing Session semantics.

Relevant docs and decisions:

- PRD #137: Intentional Settings reveal and sync recovery.
- PRD #138: Redesign Move On Celebration as Glass Bloom.
- #140: Add intentional Current Session Settings overpull.
- #141: Add inert-space all-clear dismissal.
- #142: Redesign Move On Celebration as static Glass Bloom.
- #143: Add Perfect Session bloom and reduced-motion treatment.
- #144: Review and tune Glass Bloom visual finish.
- [CONTEXT.md](../../CONTEXT.md) for Block, Week, Session, Current Session, Move On, Move On Celebration, Set,
  Set Log, RPE, and Settings language.
- [DESIGN.md](../../DESIGN.md) for the Warm Training Cockpit, Liquid Glass usage, inert-space all-clear rule,
  Current Session HUD guidance, and the intended Move On Celebration direction.
- [ADR 0001: Google Sheet as backend with local-first sync](../adr/0001-sheet-as-backend-local-first.md).
- [ADR 0004: Liquid Glass Design System](../adr/0004-liquid-glass-design-system.md), including the later note
  to preserve selective Liquid Glass layering while not reviving the superseded amber palette.
- Current code around `SessionControlsVisibility`, `SessionView`, `SessionProgressHeader`, `SmartValuePills`,
  `LoggedSetReviewCard`, `MoveOnCelebrationPresentation`, and `MoveOnCelebrationView`.

## Decisions

- Decision: Deepen the Current Session Settings reveal before changing its visual treatment.
  Source: #140.
  Consequence: A testable Session reveal state module owns thresholds, release outcomes, pinning, idle timeout,
  dismissal, Current Session gating, and reduced-motion state outcomes.

- Decision: Keep the reveal module specific to Current Session Settings.
  Source: #145 architecture direction.
  Consequence: Do not create a general Settings framework, transient UI registry, event bus, or broad gesture
  system. The module should know it reveals one Settings affordance in the Session HUD.

- Decision: Keep child editing state local unless #141 needs a narrow clear request.
  Source: Current `SmartValuePills` and `LoggedSetReviewCard` ownership.
  Consequence: Parent Session code may request an all-clear, but child views clear their own Weight/Reps focus,
  logged Set editing, or RPE grid state. The parent must not own form text, selected RPE, or draft Set Log data.

- Decision: Move On Celebration presentation owns meaning; the view owns rendering.
  Source: Current `MoveOnCelebrationPresentation` and #142/#143.
  Consequence: Week/Day context, ordered stats, pending Set count as `Left`, stable quote, Perfect Session state,
  accessibility text, haptic style, and reduced-motion/bloom intent belong in the presentation module.

- Decision: Keep human visual judgement outside the pure presentation module.
  Source: #144.
  Consequence: The presentation can expose state needed to render and test the Glass Bloom, but final polish of
  TFN logo readability, native-feeling glass, long-quote wrap, and light-mode composition remains a visual QA
  issue, not a deterministic presentation decision.

- Decision: Preserve local-first Sheet ownership and avoid write-path planning in this work.
  Source: ADR 0001 and #145 out-of-scope direction.
  Consequence: These modules must not change Google Sheet write-path behavior, `SyncCoordinator` pending-write
  flush planning, Set Log targeting, or variable Sessions-per-Week planning.

## Scope

### In

- Architecture contracts for the Current Session Settings reveal used by #140.
- Architecture contracts for inert-space all-clear behavior used by #141.
- Architecture contracts for Move On Celebration presentation and view responsibilities used by #142 and #143.
- Visual QA ownership boundaries for #144.
- Testing expectations for pure presentation/state logic, SwiftUI UI integration, accessibility, reduced motion,
  haptics, long quotes, and non-current Session exclusion.
- Documentation references to PRD #137, PRD #138, child issues #140 through #144, product/design docs, ADR 0001,
  ADR 0004, and current code paths.

### Out

- Implementing the Settings overpull reveal.
- Implementing inert-space all-clear dismissal.
- Implementing the Glass Bloom Move On Celebration redesign.
- Implementing the Perfect Session bloom animation or reduced-motion treatment.
- Performing #144 human visual QA or tuning.
- Closing, editing, relabeling, or otherwise modifying #137, #138, or child issues #140 through #144.
- Variable Sessions-per-Week behavior or fixed-day-count copy derivation.
- Google Sheet write-path changes, Set Log targeting changes, or `SyncCoordinator` pending-write flush planning.
- A general Settings framework, transient UI registry, app-wide event bus, or broad gesture abstraction.

## Current Architecture

`SessionView` is the Session orchestration surface. When `workout.displayedSession` exists, it renders
`SyncStatusBanner`, non-current Session override controls, a scrollable Session body, `OpenExercisesSection`,
`MoveOnButton`, and a top `SessionProgressHeader` HUD. It also owns `isSettingsPresented` and presents
`SettingsView`.

`SessionControlsVisibility` is a pure value with:

- `hidden` and `visible`.
- `revealOffset` of 72 points.
- `dismissOffset` of -24 points.
- `updated(topContentOffset:)`, which switches visibility from scroll geometry alone.

`SessionView.updateSessionControls(topContentOffset:)` gates the reveal with `canRevealSessionControls`.
That gate is true only when the athlete is viewing the live edge and no Move On Celebration is visible. This
already protects non-current Session views from showing Settings, but the policy is still too shallow for
preview, release-to-commit, timeout, and explicit dismissal.

`SessionProgressHeader` receives `showsSessionControls` and renders `SessionControls`, which currently contains
one icon-only Settings button with the accessibility identifier `session-controls-settings-button`. The header
also renders the Week/Day location and progress rail.

Inert-space taps are currently partial and local:

- A bottom `Color.clear` spacer in `SessionView` cancels pairing and collapses logged Set review.
- `SmartValuePills` clears its own Weight/Reps editing when its local clear background is tapped.
- `LoggedSetReviewCard` clears focus through its own controls and commits a valid draft on disappear.

The parent does not have a narrow way to ask the active child views to clear private keyboard state.

`MoveOnCelebrationPresentation` is a pure value initialized from a captured `Session`. It currently exposes:

- `weekText`
- `titleText`
- `sublineText`
- ordered stats: `Sets`, `Exercises`, `Left`
- one randomly selected approved quote held stable by the view's `@State`
- accessibility label/value
- haptic style, with `successWithImpact` for a Perfect Session

`MoveOnCelebrationView` owns the overlay, gradient background, checkmark stamp, repeated ripple animation,
copy stack, stats row, tap dismissal, and haptics. It is already the right place for animation/haptic side
effects, but it currently renders the old checkmark and title/subline hierarchy that #142 removes.

## Target Architecture

### Current Session Settings Reveal

Create a small, pure Current Session Settings reveal module behind a narrow interface. It should sit with the
existing Progress presentation/state values unless implementation proves a separate Session UI policy file is
clearer. The module should be deterministic, value-based, and directly component-testable.

The reveal module owns:

- State: hidden, previewing, pinned.
- Policy: preview threshold around 140 points, commit threshold around 190 to 210 points, resistance/progress,
  idle timeout around 2.5 seconds, and reduced-motion visual mode.
- Inputs: scroll top offset, release/settle event, Settings tap, content scroll back into Session content,
  inert-space clear request, timeout, Current Session eligibility change, and Move On Celebration visibility.
- Outputs: render state for the header, whether Settings is tappable, whether the HUD should reserve extra
  vertical space, and whether the current event should open Settings.

`SessionView` remains the owner of scroll geometry, Settings sheet presentation, current/non-current Session
knowledge, Move On Celebration overlay state, and transient all-clear requests. It calls the reveal module and
passes render state into `SessionProgressHeader`.

`SessionProgressHeader` stays shallow. It renders the Session HUD from a reveal presentation and forwards
Settings taps. It does not decide Current Session eligibility, thresholds, timeout, or dismissal semantics.

### Inert-Space All-Clear

Use a narrow Session-level clear request only if #141 requires parent-to-child clearing across private child
state. The clear request is not a general event bus. It exists to let inert Session background/gap taps ask
currently rendered Session children to dismiss transient UI.

`SessionView` owns recognition of inert Session background or gap taps. It must not attach a broad gesture that
swallows real controls. Taps on Log, Set rows, Weight/Reps pills, RPE chips, Go back, Make Current, or Settings
must perform their normal actions.

Child views remain responsible for their own state:

- `SmartValuePills` clears Weight/Reps keyboard focus and keeps RPE chip/grid behavior unchanged.
- `LoggedSetReviewCard` clears Weight/Reps keyboard focus, may dismiss its RPE grid if that is part of existing
  transient review state, and keeps valid-draft commit behavior intact.
- `SessionCoordinator` remains responsible for pairing and logged Set review collapse.

### Move On Celebration Presentation

Deepen `MoveOnCelebrationPresentation` so it contains every deterministic fact needed by the Glass Bloom
rendering:

- Week/Day context text, such as `Week N · Day X`.
- Ordered stats in the stable order `Sets`, `Exercises`, `Left`.
- `Left` as the pending Set count for the captured Session.
- Stable quote selection for one celebration display.
- Perfect Session state derived from zero pending Sets.
- Haptic style for normal incomplete Move On Celebration versus Perfect Session.
- Accessibility label/value/hint text covering Week, Day, quote, stats, and dismissal.
- Reduced-motion and bloom intent as presentation state where practical, without deciding subjective visual
  quality.

`MoveOnCelebrationView` renders the presentation, plays the selected haptic style, applies animation based on
reduce-motion environment, and dismisses when the athlete taps anywhere. It should not compute pending Sets,
select stats order, decide Perfect Session semantics, or derive accessibility content from view layout.

The visual hierarchy for #142 is:

1. faint `Week N · Day X` context
2. TFN logo as one horizontal Liquid Glass focal object
3. one bounded rotating quote that stays stable for the display
4. `Sets / Exercises / Left` stats row
5. `Tap anywhere to continue`

The old checkmark stamp and visible title/subline stack are deleted by #142. Perfect Sessions use the same
hierarchy and may get richer haptics and a native-feeling bloom in #143.

### Visual QA Boundary

Issue #144 owns human-reviewed visual judgement after #142 and #143. Deterministic code may provide fixtures
for normal incomplete, Perfect Session, and long-quote states, but the pure presentation module must not encode
subjective pass/fail rules such as "native-feeling enough" or "logo reads clearly enough."

## Contracts

### [ADDED] `CurrentSessionSettingsReveal`

A pure state value or reducer for the Settings overpull reveal.

Required behavior:

- Starts hidden.
- Ignores all reveal input when `isViewingCurrentSession` is false.
- Ignores all reveal input while a Move On Celebration is visible.
- Below the preview threshold, ordinary scroll bounce leaves the state hidden and renders no visible cue.
- At roughly 140 points of top overpull, enters previewing with progress.
- Release before the commit threshold contracts back to hidden.
- Release beyond roughly 190 to 210 points pins Settings open.
- Pinned Settings dismisses on Settings tap, scroll back into Session content, inert-space clear, timeout after
  roughly 2.5 seconds, non-current Session transition, or Move On Celebration presentation.
- Reduced motion preserves the same state outcomes while marking the render state for fade/contract treatment
  instead of motion-heavy preview.

The interface should accept value inputs and return a new value. It should not mutate shared state in place.

### [ADDED] `CurrentSessionSettingsRevealPolicy`

A small value containing thresholds and timing. Defaults should encode the #140 contract:

- preview threshold: about 140 points
- commit threshold: about 190 to 210 points
- idle timeout: about 2.5 seconds

Use named constants or a policy value so tests do not duplicate magic numbers. This is configuration for one
module, not user-facing app settings.

### [CHANGED] `SessionProgressHeader` Settings Contract

Replace the boolean `showsSessionControls` contract with a render contract that can distinguish hidden,
previewing, and pinned states.

Required rendering behavior:

- Renders at most one utility affordance: icon-only Settings.
- Provides an accessible Settings label.
- Shows no visible cue before preview begins.
- Keeps non-current Session override controls (`Go back`, `Make Current`) separate from the reveal.
- Does not own reveal legality or timeout decisions.

The existing Settings accessibility identifier may stay if it remains accurate; if renamed, UI tests must be
updated in the same implementation slice.

### [ADDED] `SessionAllClearRequest`

A narrow value signal from `SessionView` to currently rendered Session children, used only if #141 needs
parent-to-child clearing of private transient state.

Required behavior:

- Carries identity, such as an incrementing token, so children can respond once per inert-space tap.
- Means "clear transient Session UI," not "cancel the current action."
- Is emitted only from inert Session background or gap taps.
- Never fires from Log, Set rows, Weight/Reps pills, RPE chips, Go back, Make Current, or Settings.

Child responsibilities:

- `SmartValuePills` clears Weight/Reps keyboard focus and keeps its draft values.
- `LoggedSetReviewCard` clears Weight/Reps keyboard focus and keeps valid draft commit behavior.
- RPE remains chip/grid-driven and is not converted into keyboard-dismiss behavior.
- `SessionCoordinator` keeps ownership of pairing cancellation and logged Set review collapse.

### [CHANGED] `MoveOnCelebrationPresentation`

Deepen the pure presentation value.

Required presentation fields:

- `contextText`: `Week N · Day X` or equivalent Week/Day context.
- `stats`: ordered `Sets`, `Exercises`, `Left`.
- `leftSetCount`: pending Set count, exposed directly or through the `Left` stat.
- `quoteText`: selected once per presentation instance and stable for that display.
- `isPerfectSession`: true when zero Sets are pending.
- `hapticStyle`: normal success for incomplete Move On Celebration, stronger existing style for Perfect Session.
- `accessibilityLabel` and `accessibilityValue`: includes Week, Day, quote, stats, and the dismissal action.
- `bloomStyle` or equivalent deterministic state: normal, perfect, and reduced-motion-safe.

Removed presentation meaning:

- No visible `Day X Done` title requirement.
- No visible `Moved on with N left` subline requirement.
- No fixed-day-count motivational copy.

### [CHANGED] `MoveOnCelebrationView`

Keep this view shallow.

Required view responsibilities:

- Render the Glass Bloom hierarchy from `MoveOnCelebrationPresentation`.
- Keep the quote in a bounded region that can tolerate longer copy.
- Render `Left` as part of the stats row rather than a separate default hierarchy row.
- Play the haptic style chosen by the presentation.
- Use reduce-motion environment to skip repeated or unnecessary ripple motion.
- Dismiss and advance on tap anywhere without delaying advancement for animation.

The view may own visual-only animation state. It must not compute Session stats, Perfect Session state, quote
selection, or haptic semantics.

### [REMOVED] Old Move On Celebration Visual Hierarchy

Issue #142 removes the old visible focal object and copy hierarchy:

- checkmark stamp as focal object
- visible `Day X Done` title stack
- visible `Moved on with N left` subline stack

Tests should assert the new hierarchy instead of preserving old copy.

### [REMOVED] Broad Hidden-Controls Gesture Semantics

The implementation must not treat any Session tap as a global dismiss action. Only inert Session background or
gap taps clear transient UI. Real controls keep their normal actions.

## Migration Plan

### Phase 1: Current Session Settings Reveal State (#140)

- Change: Replace `SessionControlsVisibility` with the deepened Current Session Settings reveal state or wrap it
  behind a compatibility adapter while tests migrate.
- Compatibility: Keep `SessionView` as the orchestrator and keep `SessionProgressHeader` as the render surface.
- Acceptance criteria: Component tests prove hidden, previewing, release-to-hidden, release-to-pinned, timeout,
  Settings tap dismissal, content-scroll dismissal, Current Session-only gating, non-current exclusion, and
  reduced-motion state outcomes. UI tests cover ordinary bounce, intentional overpull, tapping Settings,
  idle/scroll dismissal, and non-current Session exclusion.

### Phase 2: Inert-Space All-Clear (#141)

- Change: Add inert-space tap recognition in `SessionView` and a narrow clear request only if needed to reach
  child private editing state.
- Compatibility: Child views keep form text, selected RPE, and validation logic local. Real controls remain
  tappable and are not swallowed by a parent gesture.
- Acceptance criteria: UI tests cover active Set Weight/Reps keyboard dismissal, logged Set review Weight/Reps
  keyboard dismissal, pinned Settings dismissal, preservation of RPE chip/grid behavior, and normal behavior for
  Log, Set rows, Weight/Reps pills, RPE chips, Go back, Make Current, and Settings.

### Phase 3: Static Glass Bloom Presentation (#142)

- Change: Deepen `MoveOnCelebrationPresentation` around Week/Day context, stats order, `Left`, stable quote,
  accessibility, and haptic semantics. Update `MoveOnCelebrationView` to render the static Glass Bloom hierarchy
  and remove the old stamp/title/subline hierarchy.
- Compatibility: Tapping Move On still captures the Session, shows a Move On Celebration, and advances only when
  the athlete taps anywhere to dismiss.
- Acceptance criteria: Presentation/component tests cover context text, stats order, pending Set count as `Left`,
  quote stability, haptic style preservation, and accessibility text. UI tests assert the new visible hierarchy.
  `DESIGN.md` receives the #142 design-system update. `PRODUCT.md` remains unchanged unless a new product
  principle is discovered.

### Phase 4: Perfect Session Bloom and Reduced Motion (#143)

- Change: Add Perfect Session bloom intent and reduced-motion behavior on top of the static hierarchy.
- Compatibility: Perfect Sessions keep the same overall hierarchy as incomplete Move On Celebrations and keep
  the stronger haptic style. Dismissal and advancement are not delayed by animation.
- Acceptance criteria: Tests cover normal haptic style, Perfect Session haptic style, reduced-motion behavior
  where practical, and robust presentation state for long quotes and Dynamic Type.

### Phase 5: Human Visual QA and Tuning (#144)

- Change: Capture simulator screenshots for normal incomplete, Perfect Session, and long-quote Move On
  Celebration states in the accepted light appearance direction. Tune only the Move On Celebration if human
  review finds visual issues.
- Compatibility: No Session View, Block grid, appearance settings, Sheet sync, or Move On behavior redesign
  belongs in this phase.
- Acceptance criteria: Human review confirms or directs scoped tuning for TFN logo readability, native-feeling
  glass treatment, long-quote wrap, visible stats/hint, reduced-motion behavior, and rejected copy avoidance.

## Deletion Criteria

- Delete or fully replace the old two-state `SessionControlsVisibility` once #140 tests cover the deepened
  reveal state and no caller depends on `showsSessionControls: Bool`.
- Delete old UI tests or assertions that require the checkmark stamp, `Day X Done`, or `Moved on with N left`
  visible hierarchy once #142 lands.
- Delete any temporary compatibility adapter between old and new Move On Celebration presentation fields once
  `MoveOnCelebrationView`, developer preview surfaces, and UI tests use the deepened presentation.
- Do not delete child-owned form state in `SmartValuePills` or `LoggedSetReviewCard`; all-clear should clear
  focus/transient UI without moving draft ownership to the parent.
- Do not delete or weaken SyncCoordinator pending-write behavior, Set Log write targeting, or local cache
  behavior as part of these modules.

## Acceptance Criteria

- [ ] #140 can be implemented from this spec without another architecture pass.
- [ ] #141 can be implemented from this spec without another architecture pass.
- [ ] #142 can be implemented from this spec without another architecture pass.
- [ ] #143 can be implemented from this spec without another architecture pass.
- [ ] #144 has a clear boundary between deterministic presentation/module work and human visual judgement.
- [ ] The Current Session Settings reveal remains specific to Settings in the Session HUD.
- [ ] The all-clear design preserves child ownership of private Weight/Reps and logged Set review state.
- [ ] The Move On Celebration presentation owns deterministic Session meaning, while the view owns rendering,
  animation, haptics, and dismissal.
- [ ] Variable Sessions-per-Week, Google Sheet write-path changes, and `SyncCoordinator` pending-write flush
  planning are explicitly out of scope.
- [ ] The spec references #137, #138, #140, #141, #142, #143, #144, `CONTEXT.md`, `PRODUCT.md`, `DESIGN.md`,
  ADR 0001, ADR 0004, and current code paths without copying PRD bodies.
- [ ] No implementation files are modified by this spec slice.

## Testing Strategy

- Use Swift Testing component tests for pure state/presentation modules:
  - Current Session Settings reveal thresholds, state transitions, timeout, dismissal events, Current Session
    gating, non-current exclusion, and reduced-motion state outcomes.
  - Move On Celebration context text, stats order, pending Set count as `Left`, quote stability, haptic style,
    Perfect Session state, accessibility text, and reduced-motion/bloom intent.
- Use UI integration tests for SwiftUI behavior:
  - ordinary scroll bounce does not reveal Settings
  - intentional overpull previews and pins Settings only for the Current Session
  - Settings tap opens Settings and dismisses the pinned pill
  - idle timeout and content scroll dismiss the pinned pill
  - non-current Session views with Go back and Make Current do not expose the overpull reveal
  - inert Session background/gap taps dismiss active and logged Set Weight/Reps keyboard editing
  - real controls still perform their normal actions while all-clear behavior exists
  - Move On shows the new Glass Bloom hierarchy and tap anywhere dismisses/advances
- Use simulator screenshot review for #144 only after #142 and #143 land. Static screenshots should include
  normal incomplete, Perfect Session, long quote, reduced motion, and accepted light appearance direction.
- Continue running the repo's required gates for implementation branches: `swift test`, Xcode
  `WorkoutTrackerTests`, Xcode `WorkoutTrackerUITests`, and `swiftlint lint --quiet`.

## Open Questions

- The exact concrete name for the Settings reveal type can be chosen during #140, but it must remain specific
  to Current Session Settings reveal.
- The exact representation of `bloomStyle` can be chosen during #143 once the implementation proves whether the
  richer bloom reads as native Liquid Glass or should collapse to the static lens.
- #141 should confirm whether logged Set review RPE grid dismissal is part of existing transient review state;
  RPE must not become keyboard-dismiss behavior either way.
