# Settings Reveal and Glass Bloom Presentation Seams Spec

## Goal

Define the architecture seams for the next Current Session Settings reveal and Move On Celebration work without
implementing those features in this issue.

The first implementation target is the Current Session Settings reveal, including the inert-space all-clear seam
needed by #141. The second implementation target is the Move On Celebration Glass Bloom presentation. The spec
turns the settled architecture answers from #146 into module ownership, contracts, migration phases, deletion
criteria, and test surfaces so later implementation issues can proceed without another architecture pass.

## Background

The athlete uses the app on the gym floor to read prescribed Sets, log Set Logs, and choose Move On from the
Current Session. [CONTEXT.md](../../CONTEXT.md) defines Current Session as the Available Session the athlete is
actively working on, Move On as the explicit action that advances past the Current Session, and Move On
Celebration as the acknowledgement shown after that action. Those terms are the required vocabulary for the
contracts below.

[PRODUCT.md](../../PRODUCT.md) says the product should be warm, focused, and trustworthy: logging remains the
main Session activity; sync should be automatic by default with manual recovery in Settings; celebration should
be earned and occasional, not gamified or loud. [DESIGN.md](../../DESIGN.md) extends that with the Warm Training
Cockpit, selective Liquid Glass, a Current Session HUD that may reveal an icon-only Settings pill only through an
intentional high-effort overpull, and an inert-space all-clear rule for transient Session UI.

[ADR 0001](../adr/0001-sheet-as-backend-local-first.md) keeps the Google Sheet as the source of truth and the
app as a local-first read-write client. This spec does not change Sheet parsing, Set Log writes, pending writes,
or sync ownership. [ADR 0004](../adr/0004-liquid-glass-design-system.md) keeps selective Liquid Glass layering
and platform chrome while its older amber palette is superseded by the current Dark and Sage Light directions in
`DESIGN.md`.

Live issue context:

- #137 defines the product contract for an intentional Settings reveal and sync recovery.
- #138 defines the product contract for the Glass Bloom Move On Celebration.
- #139 is closed and already moved manual sync into Settings as **Sync now**. Because it remains closed, manual
  sync recovery is not an architecture candidate here; it belongs to Settings and stays out of the Session HUD.
- #140 is the Current Session Settings overpull implementation target.
- #141 is the inert-space all-clear dismissal target and belongs with the Settings reveal work as a small
  clear-request seam.
- #142 is the static Glass Bloom Move On Celebration target.
- #143 is the Perfect Session bloom and reduced-motion treatment target.
- #144 is the human visual QA pass. It owns subjective visual judgement and must stay outside pure presentation
  logic.

Current source facts:

- `SessionControlsVisibility` in `WorkoutTracker/Progress/ActiveSetPresentation.swift` is a two-state value
  (`hidden` or `visible`) driven only by scroll offset thresholds.
- `SessionView` owns scroll geometry, the Settings sheet, non-current Go back / Make Current controls, Move On
  Celebration overlay presentation, and local transient cleanup through `SessionCoordinator`.
- `SessionProgressHeader` receives `showsSessionControls: Bool` and conditionally renders one icon-only
  Settings button.
- `SmartValuePills` and `LoggedSetReviewCard` own private Weight/Reps editing state. That state should remain
  child-owned.
- `MoveOnCelebrationPresentation` currently exposes `weekText`, `titleText`, `sublineText`, ordered stats,
  `quoteText`, accessibility text, and haptic style.
- `MoveOnCelebrationView` owns the visual overlay, old checkmark stamp/ripple, old title/subline hierarchy,
  tap-anywhere dismissal, and haptics.

## Decisions

- Decision: Current Session Settings reveal is the first implementation target.
  Source: #146, #137, #140, `DESIGN.md`.
  Consequence: Build one small pure reveal state module before broad SwiftUI changes. Do not build generic
  Settings infrastructure or a general transient UI framework.

- Decision: Move On Celebration presentation is the second implementation target.
  Source: #146, #138, #142, #143.
  Consequence: Replace old title/subline semantics with Glass Bloom presentation facts before or alongside the
  view redesign. The view renders the facts; it does not compute Session meaning.

- Decision: Manual sync recovery is not an architecture candidate while #139 remains closed.
  Source: #139 closed state, `PRODUCT.md`, `DESIGN.md`.
  Consequence: The Session HUD exposes no sync affordance. Settings owns **Sync now** near Training Sheet
  connection controls.

- Decision: #141 inert-space all-clear belongs with Settings reveal as a narrow clear-request seam.
  Source: #141, `DESIGN.md`.
  Consequence: Use a parent-issued request token to let children clear private transient UI. Do not create an
  app-wide transient UI event bus.

- Decision: Keep pure behavior separate from SwiftUI adapter behavior for both candidates.
  Source: #146 architecture answers, existing pure presentation values.
  Consequence: Reducer-like or presentation values own deterministic facts; SwiftUI owns gestures, geometry,
  timers, sheets, haptics, animation, materials, and visual judgement.

- Decision: Do not pursue variable Sessions-per-Week as part of this spec.
  Source: #146 and `CONTEXT.md`.
  Consequence: The current Block model remains four Weeks with four Sessions each. Celebration copy should avoid
  fixed day-count phrases, but this spec does not change parsing or domain cardinality.

- Decision: Human visual QA remains outside deterministic presentation.
  Source: #144.
  Consequence: Pure presentation may expose facts needed by the view, but it must not decide whether a glass
  bloom looks native, whether the TFN logo reads clearly, or whether a screenshot is polished enough.

## Scope

### In

- Current Session Settings reveal ownership, state, presentation facts, command outcomes, and testing surfaces.
- The narrow inert-space all-clear request seam for #141.
- Move On Celebration presentation ownership, fields, quote stability, accessibility, haptic facts, and testing
  surfaces.
- SwiftUI adapter responsibilities for both candidates.
- Migration phases that can be reviewed independently while preserving current behavior until replacement.
- Deletion criteria for `SessionControlsVisibility`, old Session Controls assumptions, and old Move On
  Celebration title/subline presentation fields.
- Explicit out-of-scope decisions needed to keep later AFK implementation issues focused.

### Out

- Implementing #140, #141, #142, #143, or #144.
- Moving manual sync again, adding pull-to-refresh, or changing Settings **Sync now** behavior from #139.
- A generic Settings module.
- An app-wide transient UI event bus or central registry.
- A one-adapter protocol seam that abstracts only one concrete SwiftUI caller.
- Leaving `SessionView` responsible for every reveal sub-state.
- A quote-management subsystem, quote persistence, remote config, quote history, weighted rotation, or editorial
  tooling.
- A new app-wide theme variant.
- Encoding subjective native-glass judgement in pure presentation logic.
- Changing Sheet parsing, Set Log write targeting, pending-write flushing, or local-first sync contracts.
- Variable Sessions-per-Week parsing or domain model changes.

## Current Architecture

### Current Session Settings Reveal

`SessionView` observes top scroll geometry through `onScrollGeometryChange`, computes top overpull, and calls
`updateSessionControls(topContentOffset:)`. That function applies `canRevealSessionControls`, which is true only
when the athlete is viewing the live edge and no Move On Celebration is visible.

If reveal is allowed, `SessionControlsVisibility.updated(topContentOffset:)` turns the state visible at a low
reveal offset and hides it below a dismiss offset. The value cannot represent previewing, release-to-commit,
pinning, idle timeout, scroll-back dismissal, inert-space dismissal, reduced-motion presentation, or command
outcomes.

`SessionProgressHeader` receives a boolean and renders `SessionControls`, which contains one icon-only Settings
button. It does not decide whether reveal is legal, which is good. The boolean contract is still too shallow for
#140.

Non-current Session views render `CurrentSessionOverrideControls` with Go back and Make Current above the
scrollable content. Those controls must remain separate from the hidden Settings reveal.

### Inert-Space All-Clear

Current inert-space cleanup is local and incomplete. `SessionView` has a bottom clear spacer that cancels pairing
and collapses logged Set review. `SmartValuePills` and `LoggedSetReviewCard` own their own Weight/Reps editing
state and clear it locally. There is no narrow parent-to-child signal for "an inert Session gap was tapped" that
children can handle once without exposing their private focus bindings.

### Move On Celebration

`WorkoutStore.requestMoveOnCelebration()` captures the Session before advancement. `SessionView` overlays
`MoveOnCelebrationView`, and dismissal calls `WorkoutStore.dismissMoveOnCelebration()` to advance from the
captured Session.

`MoveOnCelebrationPresentation` is already a pure value, but its fields reflect the old hierarchy:
`weekText`, `titleText`, and `sublineText` alongside stats, quote, accessibility, and haptic style. `quoteText`
is randomly selected during initialization, which gives a stable quote for one presentation instance.

`MoveOnCelebrationView` renders the old checkmark stamp, repeated ripple animation, large quote, Week text,
`Day X Done` title, separate `Moved on with N left` or `Perfect session` subline, stats row, and tap hint. That
is the layer that should own TFN logo rendering, glass lens construction, bloom/ripple animation, Dynamic Type
wrapping, haptic playback, and tap-anywhere dismissal.

## Target Architecture

### Current Session Settings Reveal

Create one pure Current Session reveal state module. It may live near other `Progress` presentation/state values
unless implementation reveals a clearer file boundary, but it is not a generic Settings or transient UI module.

The smallest useful interface accepts:

- whether reveal is allowed for the current screen context
- top overpull distance
- release event
- scroll-back-into-content event
- idle-timeout event
- inert-space clear event
- Settings-tapped event
- reduced-motion preference

It returns:

- reveal state: hidden, previewing, pinned, or dismissing/hidden-after-clear
- presentation facts for SwiftUI: progress, should show Settings pill, transition style, accessibility label,
  and accessibility hint
- optional command-like outcomes: open Settings, schedule idle timeout, cancel idle timeout

The pure module owns preview and commit thresholds, pinning rules, timeout eligibility, scroll-dismiss rules,
Current Session gating as an input-driven rule, inert-space clear semantics for the Settings pill, and
reduced-motion presentation facts. The module should use immutable value transitions: callers pass the previous
value plus an event and receive a new value plus outcomes.

The pure module does not own SwiftUI gestures, geometry readers, scroll APIs, timers, sheets, animations, actual
navigation to Settings, keyboard focus implementation inside child editors, or visual judgement about whether a
glass material looks native.

The SwiftUI adapter owns:

- reading scroll geometry and converting it to top overpull distance
- detecting release, scroll-back, inert-space tap, timeout, and Settings tap events
- scheduling and canceling the real idle timer from module outcomes
- rendering the HUD stretch/materialization from module presentation facts
- opening the Settings sheet when the module emits the open-Settings outcome
- keeping Go back and Make Current separate on non-current Session views

`SessionView` should feed events into the module and render the returned state. It should not branch on every
reveal sub-state in scattered places. A small render switch near the HUD is acceptable.

### Inert-Space All-Clear

Use a parent-issued clear request, not a central transient UI registry.

The parent Session surface should hold a monotonically increasing clear request token, such as a lightweight
`SessionClearRequest(id: Int)`. Tapping inert Session background or gaps increments the token and also sends an
inert-clear event to the Settings reveal module.

Child editors receive the current token and compare it with their last handled token. If the token changes, they
clear only their own private transient state:

- active Set Weight/Reps keyboard focus
- logged Set review Weight/Reps keyboard focus
- local RPE grid only where #141 explicitly allows all-clear to dismiss it

Children do not expose focus bindings to the parent. The parent does not know each child editor's private
implementation. Real controls and cards must not fire the inert-space clear gesture.

### Move On Celebration Presentation

Deepen `MoveOnCelebrationPresentation` so it replaces the old title/subline fields with presentation facts that
match Glass Bloom:

- `contextText`: faint `Week N - Day X`, `Week N · Day X`, or the exact typography-safe equivalent chosen
  during implementation after checking repo style
- `quoteText`: one stable approved quote for the presentation instance
- `stats`: ordered `Sets`, `Exercises`, `Left`
- `tapHintText`: `Tap anywhere to continue`
- `isPerfectSession`: boolean presentation fact
- `pendingSetCount`: if needed for accessibility or tests; the visual hierarchy should use the `Left` stat
- `accessibilityLabel`
- `accessibilityValue`
- `accessibilityHint`
- `hapticStyle`
- optional deterministic visual fact such as `visualEmphasis` or `motionTreatment`

The visual hierarchy should not expose `Day X Done` or a separate `Moved on with N left` row. Incomplete Move On
remains successful; the `Left` stat is the honest pending-set signal.

The pure presentation module owns Week/Day context text, ordered stats and values, stable quote selection,
Perfect Session detection, haptic style, accessibility text including quote and stats, and any non-subjective
visual eligibility fact needed by the view.

The pure presentation module does not own TFN logo rendering, glass lens construction, bloom/ripple
implementation, native-glass quality judgement, screenshot review, quote editing, quote persistence, or quote
management.

The SwiftUI view owns the Sage Light-led screen composition, TFN logo asset rendering, horizontal glass lens
layout, optional bloom/ripple animation, Dynamic Type wrapping behavior, reduced-motion animation suppression
when the environment requires it, tap-anywhere dismissal gesture, haptic playback from the presentation haptic
style, and screenshot-verifiable visual polish.

Reduced motion should be treated carefully. If reduced motion only changes SwiftUI animation mechanics, keep it
in the SwiftUI adapter. If the view needs a pure presentation fact, expose only deterministic eligibility such
as a motion treatment category; do not encode animation mechanics or subjective quality.

### Visual QA Boundary

#144 remains the human visual QA slice. Deterministic tests can prove that the presentation exposes normal,
Perfect Session, and long-quote states; UI tests can prove that required labels and hints are visible or
accessible. The pass/fail judgement for native-feeling glass, TFN logo readability, and final light-mode polish
belongs to human screenshot review, not pure code.

## Contracts

### [ADDED] Current Session Settings reveal state

Stable shape:

- inputs: context eligibility, top overpull, release, scroll-back, idle timeout, inert clear, Settings tap,
  reduced motion
- state: hidden, previewing, pinned, dismissing/hidden-after-clear
- presentation: progress, shouldShowSettingsPill, transition style, accessibility label, accessibility hint
- outcomes: none, open Settings, schedule idle timeout, cancel idle timeout

Required behavior:

- Hidden remains hidden below the preview threshold.
- Preview begins around the high preview threshold.
- Release before commit returns hidden.
- Release past commit pins the Settings pill.
- Pinned state emits or permits open Settings on Settings tap.
- Scroll-back dismisses pinned state.
- Idle timeout dismisses pinned state.
- Inert-space clear dismisses pinned state.
- Reveal is unavailable when Current Session gating is false.
- Reduced motion reaches the same states while returning a reduced-motion presentation style.
- The module has no dependency on SwiftUI, timers, sheets, or global mutable state.

### [ADDED] Current Session Settings reveal policy

Stable shape:

- preview threshold policy value
- commit threshold policy value
- idle timeout policy value
- optional progress mapping value for preview rendering

Required behavior:

- Defaults encode the #140 thresholds: preview around 140 points, commit roughly 190 to 210 points, timeout
  around 2.5 seconds.
- Tests use the policy values rather than duplicating magic numbers.
- The policy is module configuration, not a user-facing setting.

### [CHANGED] Session HUD Settings render contract

Replace the boolean `showsSessionControls` contract with a reveal presentation contract rich enough for hidden,
previewing, pinned, and reduced-motion rendering.

Required behavior:

- The HUD renders at most one utility affordance: icon-only Settings.
- The Settings affordance has stable accessibility label and hint text.
- No visible cue appears before preview begins.
- Non-current Session Go back and Make Current controls remain separate and do not share reveal state.
- The header does not own reveal legality, thresholds, timeout, or Settings-sheet presentation.
- The Session HUD does not render a sync button or expose a sync accessibility identifier.

### [REMOVED] Old Session Controls assumptions

Remove the assumption that Session Controls are a generally visible control group with an easy scroll-offset
threshold.

Removed behavior:

- a low-effort boolean reveal
- generic `Session Controls` semantics around the utility affordance
- any expectation that manual sync belongs in the Session HUD
- any implementation path where non-current Session views can reveal Settings by overpulling

### [ADDED] Session clear request

Stable shape:

- identity token, such as an increasing integer
- issued by the parent Session surface only from inert background or gap taps
- passed to child editors as a value

Required behavior:

- A new request is distinguishable from the previous request.
- Repeated handling of the same request is idempotent.
- Child-owned focus clearing can happen without parent knowledge of child fields.
- The same inert tap also sends the Settings reveal module an inert-clear event.
- Real controls and cards do not issue this request.

### [CHANGED] Child transient UI clearing contract

Child editors keep private ownership of transient editing state while accepting the parent clear request value.

Required behavior:

- Active Set Weight/Reps keyboard focus clears on a new request.
- Logged Set review Weight/Reps keyboard focus clears on a new request.
- Local RPE grid behavior changes only where #141 explicitly says all-clear may dismiss it.
- Draft Set Log values and valid commit-on-disappear behavior remain child-owned.
- Parent code does not receive child focus bindings, selected RPE, or draft values.

### [CHANGED] Move On Celebration presentation fields

Replace old title/subline-oriented presentation with Glass Bloom presentation facts.

Required fields:

- `contextText`
- `quoteText`
- ordered `stats`
- `tapHintText`
- `isPerfectSession`
- `pendingSetCount` if needed for accessibility or tests
- `accessibilityLabel`
- `accessibilityValue`
- `accessibilityHint`
- `hapticStyle`
- optional deterministic `visualEmphasis` or `motionTreatment`

Required behavior:

- `contextText` includes Week and Day for the captured Session.
- Stats stay ordered as `Sets`, `Exercises`, `Left`.
- The `Left` stat carries Pending Set count.
- Perfect Session detection is based on zero Pending Sets.
- Perfect Sessions use the stronger haptic style; incomplete Move On Celebrations use the normal success style.
- Accessibility text includes Week, Day, quote, stats, and the dismissal action.
- The selected quote belongs to the approved list and is stable for one presentation instance.
- An injected quote selector or initialization-time selection can force a long quote fixture for tests.

### [REMOVED] Old Move On Celebration title/subline contract

Remove the presentation contract that makes `titleText` and `sublineText` first-class visible hierarchy fields.

Removed behavior:

- visible `Day X Done` as the celebration title
- visible `Moved on with N left` as a separate row
- visual hierarchy that treats incomplete Move On as less successful than a Perfect Session
- UI tests that assert old title/subline copy as the primary celebration behavior

### [CHANGED] Move On Celebration SwiftUI rendering contract

The view consumes the pure presentation and owns visual rendering.

Required behavior:

- renders faint Week/Day context
- renders the TFN logo as the Glass Bloom focal object
- renders one bounded quote
- renders `Sets`, `Exercises`, `Left` stats in order
- renders `Tap anywhere to continue`
- supports tap-anywhere dismissal and captured-Session advancement flow
- suppresses repeated or unnecessary motion when Reduced Motion is enabled
- keeps #144 visual judgement outside pure presentation logic

## Migration Plan

### Phase 1: Settings Reveal Pure State

- Change: Introduce the Current Session Settings reveal state and policy behind component tests.
- Compatibility: Keep the existing boolean Session HUD rendering until the adapter is ready.
- Acceptance criteria:
  - The pure reveal state covers threshold, release, pin, timeout, scroll-back, inert-clear, gating, and reduced
    motion outcomes.
  - No SwiftUI view needs to adopt the new state in this phase.

### Phase 2: Settings Reveal SwiftUI Adapter

- Change: Replace `SessionControlsVisibility` usage in `SessionView` and `SessionProgressHeader` with the new
  reveal presentation/outcome contract.
- Compatibility: Preserve Settings sheet presentation and non-current Go back / Make Current behavior.
- Acceptance criteria:
  - Ordinary bounce does not reveal Settings.
  - Intentional high overpull reveals one icon-only Settings pill.
  - Tapping Settings opens Settings and dismisses pinned utility state.
  - Scroll-back and timeout dismiss pinned utility state.
  - Non-current Session views do not reveal Settings through overpull.
  - The Session HUD still exposes no manual sync affordance.

### Phase 3: Inert-Space All-Clear Seam

- Change: Add the parent clear request token and wire child editors to handle new tokens while keeping their
  private focus state local.
- Compatibility: Preserve existing pairing cancellation, logged Set review collapse, Set Log draft behavior,
  and all real control actions.
- Acceptance criteria:
  - Inert background/gap taps dismiss pinned Settings and Weight/Reps keyboard editing on active and logged Set
    surfaces.
  - Repeated handling of the same token is idempotent.
  - Tapping Log, Set rows, Weight/Reps pills, RPE chips, Go back, Make Current, or Settings performs the normal
    action.

### Phase 4: Glass Bloom Presentation Module

- Change: Replace old Move On Celebration presentation fields with Glass Bloom fields and quote-stability
  support.
- Compatibility: Preserve the existing request-before-advance and dismiss-then-advance store behavior.
- Acceptance criteria:
  - Component tests cover context text, stats order, pending Set count, Perfect Session haptic style, normal
    haptic style, quote stability, and accessibility text.
  - UI code can still render the existing celebration until the visual slice replaces it, if the implementation
    is split.

### Phase 5: Glass Bloom SwiftUI View

- Change: Render the Glass Bloom hierarchy from the new presentation and remove the old checkmark/title/subline
  visual stack.
- Compatibility: Keep tap-anywhere dismissal and captured-Session advancement.
- Acceptance criteria:
  - Move On Celebration appears before advancement.
  - Tapping anywhere dismisses and advances from the captured Session.
  - Visible hierarchy is context, TFN glass focal object, bounded quote, stats row, and tap hint.
  - Long quote fixture can wrap without hiding stats or tap hint.
  - Reduced Motion keeps the static glass lens and skips repeated ripple motion.

### Phase 6: Human Visual QA Slice

- Change: Use #144 to capture simulator screenshots and tune only the Move On Celebration visual finish.
- Compatibility: No pure presentation logic should change just because a human judges a bloom/ripple as native
  or not native.
- Acceptance criteria:
  - Normal incomplete, Perfect Session, and long-quote screenshots are reviewed in the accepted light appearance.
  - Any tuning remains scoped to Move On Celebration.

## Deletion Criteria

- Delete `SessionControlsVisibility` after the new reveal state module drives the HUD and its component tests
  cover hidden, previewing, pinned, timeout, scroll-back, inert-clear, non-current gating, and reduced-motion
  outcomes.
- Delete old `showsSessionControls` boolean plumbing after `SessionProgressHeader` accepts a reveal render
  contract and UI tests cover ordinary bounce, intentional overpull, Settings tap, dismissal, and non-current
  exclusion.
- Delete old Session Controls naming or accessibility identifiers after replacement UI tests target the
  Settings-only affordance and no tests or views depend on generic Session Controls semantics.
- Delete any remaining Session HUD sync assumptions after Settings-hosted **Sync now** coverage remains green
  and no Session HUD sync accessibility identifier exists.
- Delete `MoveOnCelebrationPresentation.titleText` and `sublineText` after Glass Bloom presentation tests cover
  context text, stats, quote, haptic style, and accessibility, and UI tests no longer assert `Day X Done` or
  `Moved on with N left`.
- Delete old checkmark/ripple stamp view code after the TFN glass focal object ships and #144 either accepts the
  bloom/ripple or explicitly scopes it down to the static glass lens.

## Acceptance Criteria

- [ ] The spec exists at `docs/specs/2026-06-01-settings-reveal-glass-bloom-presentation-seams.md`.
- [ ] The spec follows the required sections: Goal, Background, Decisions, Scope, Current Architecture, Target
      Architecture, Contracts, Migration Plan, Deletion Criteria, Acceptance Criteria, Testing Strategy, and
      Open Questions.
- [ ] Every contract is tagged `[ADDED]`, `[CHANGED]`, or `[REMOVED]`.
- [ ] Pure state/presentation behavior is separated from SwiftUI adapter behavior for Current Session Settings
      reveal and Move On Celebration.
- [ ] Migration phases are independently reviewable and preserve current behavior until replacement.
- [ ] Deletion criteria cover `SessionControlsVisibility`, old Session Controls assumptions, and old Move On
      Celebration title/subline fields.
- [ ] The spec cites `CONTEXT.md`, `PRODUCT.md`, `DESIGN.md`, ADR 0001, ADR 0004, and issue numbers #137 through
      #144.
- [ ] The spec keeps #144 human visual QA outside pure presentation logic.
- [ ] The spec avoids feature implementation and limits examples to interface-shaped contracts.
- [ ] The architecture answers from #146 are documented as settled decisions rather than reopened questions.

## Testing Strategy

### Component Tests

Current Session Settings reveal tests should exercise the same pure interface SwiftUI calls:

- hidden below preview threshold
- preview begins around the high preview threshold
- release before commit returns hidden
- release past commit pins the Settings pill
- pinned state emits or permits Settings open on Settings tap
- scroll-back dismisses pinned state
- idle timeout dismisses pinned state
- inert-space clear dismisses pinned state
- reveal is unavailable when Current Session gating is false
- reduced motion reaches the same states while returning the reduced-motion presentation style

All-clear component tests should verify request-token semantics without testing SwiftUI focus directly:

- a new clear request is distinguishable from the previous one
- repeated handling of the same request is idempotent
- child-owned focus clearing can happen without parent knowledge of child fields

Move On Celebration presentation tests should verify:

- context text includes Week and Day
- stats are ordered as `Sets`, `Exercises`, `Left`
- `Left` carries pending Set count
- Perfect Sessions use the stronger haptic style
- incomplete Move On Celebrations use the normal haptic style
- quote selection is stable for a single presentation instance
- injected or initialization-time quote selection can force a long quote fixture
- accessibility label/value/hint include Week, Day, quote, stats, and dismissal action

### UI Integration Tests

Settings reveal UI tests should verify observable behavior:

- ordinary bounce does not reveal Settings
- intentional high overpull reveals one icon-only Settings pill
- tapping the Settings pill opens Settings
- Session HUD does not expose a sync button
- scroll-back or idle timeout dismisses the pinned pill
- tapping inert Session space dismisses the pinned pill
- non-current Session views with Go back and Make Current do not reveal Settings through overpull
- active Set Weight keyboard dismisses on inert-space tap
- active Set Reps keyboard dismisses on inert-space tap
- logged Set review Weight keyboard dismisses on inert-space tap
- logged Set review Reps keyboard dismisses on inert-space tap
- tapping Log, Set rows, Weight/Reps pills, RPE chips, Go back, Make Current, or Settings performs the normal
  action instead of being swallowed

Move On Celebration UI tests should move away from old visual copy:

- stop asserting `Day X Done`
- stop asserting visible `Moved on with N left`
- assert the Move On Celebration appears before advancement
- assert accessible context includes Week and Day
- assert quote exists and is readable
- assert `Sets`, `Exercises`, and `Left` stat labels/values exist in order
- assert `Tap anywhere to continue` remains visible
- assert tapping anywhere dismisses and advances from the captured Session
- assert old rejected copy does not appear as visual hierarchy where practical

Store-level tests that prove request-before-advance and dismiss-then-advance behavior should remain in place.

### Visual QA

#144 owns screenshot review for subjective finish. The implementation slices should provide deterministic fixture
states for normal incomplete, Perfect Session, and long-quote celebrations, but pure presentation tests should
not assert that a bloom looks native or that the TFN logo is visually polished.

## Open Questions

None. The architecture answers in #146 are settled for this spec. Later implementation issues may choose exact
type names, file placement, and typography-safe punctuation, but those choices must preserve the contracts above.
