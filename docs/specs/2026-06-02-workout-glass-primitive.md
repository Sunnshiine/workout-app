# WorkoutGlass Primitive Spec

## Goal

Replace the 36 hand-repeated Liquid Glass call sites scattered across 12 SwiftUI view
files with a single internal helper, `WorkoutGlass`, that owns the app's glass treatment.
Every glass surface, button, container, and morphing identity will route through this one
seam so the glass look can change in one place instead of 36. This is a **pure refactor**:
no visible or behavioral change to the app.

## Background

The app adopted native iOS 26 Liquid Glass per [ADR 0004](../adr/0004-liquid-glass-design-system.md),
which deliberately kept styling inline and declined custom ViewModifiers while the app was
small ("A single `Theme.swift` file holds all visual constants... No custom ViewModifiers
until the app grows to warrant them"). The app has since grown to **36 native glass call
sites across 12 views**, and changing the glass look now means editing all 36 by hand.

[PR #166](https://github.com/Sunnshiine/workout-app/pull/166) (`docs/proposals/swift-frameworks-reuse-proposal.md`)
evaluated this and recommends: keep Liquid Glass **native** (Apple's SwiftUI APIs, already in
use), add a **tiny internal helper** to remove the repeated boilerplate (Priority 2: "Pilot
internally"), and **avoid third-party Liquid Glass kits** (Priority 9: "Avoid for now").

This spec realizes the internal-helper direction, scoped per decisions made during a grilling
session (below).

## Decisions

- **Decision:** Build an internal `WorkoutGlass` helper over Apple's native glass APIs; do not
  add any package (no third-party glass kit).
  - **Source:** PR #166 proposal, Priorities 2 & 9.
  - **Consequence:** Zero new runtime dependencies; the seam is fully app-owned and auditable.

- **Decision:** Route **all 36** glass call sites through the helper — surfaces, buttons,
  containers, and morph IDs — not only the surface duplicates the proposal flagged.
  - **Source:** Grilling session, 2026-06-02 (user override of the proposal's narrower scope).
  - **Consequence:** Container/morph-ID wrappers are thin pass-throughs that move structural
    choices behind a name; accepted as the cost of a single seam.

- **Decision:** Expose the **complete** native glass vocabulary (prominence `.regular`/`.clear`,
  `.tint`, `.interactive`, `.glass` + `.glassProminent` buttons, container, morph id, union,
  transition), not just APIs in use today.
  - **Source:** Grilling session, 2026-06-02.
  - **Consequence:** Some entries are unused on day one (a deliberate trade against YAGNI);
    each ships as a thin pass-through so it adds vocabulary, not machinery.

- **Decision:** Helper uses a **ViewModifier / button-style / container-type** form
  (`.workoutGlass(.card)`, `.buttonStyle(.workoutGlass)`, `WorkoutGlassContainer { }`), not the
  proposal's value-and-constant form.
  - **Source:** Grilling session, 2026-06-02 (the value form cannot wrap buttons/containers).
  - **Consequence:** Call sites read in domain terms; all Apple syntax lives in one file.

- **Decision:** Record this reversal by updating [ADR 0004](../adr/0004-liquid-glass-design-system.md)
  with a dated note (rather than a new ADR).
  - **Source:** Grilling session, 2026-06-02.
  - **Consequence:** ADR 0004's "no custom ViewModifiers" line is superseded in place.

## Scope

### In

- A new `WorkoutGlass` helper file under `WorkoutTracker/Views/`.
- Migration of all 36 existing glass call sites in the 12 view files to the helper.
- Promotion of the local `lensCornerRadius` constant into `Theme`.
- A dated supersession note appended to ADR 0004.

### Out

- Any visual or behavioral change to glass surfaces (pure refactor; pixel-identical output).
- New glass features, new tinted/interactive/prominent usages (the vocabulary exists, but no
  call site adopts it as part of this work).
- Adoption of the proposal's other priorities (`swift-dependencies`, snapshot testing,
  collections, etc.) — separate work.
- Any change to `Theme.swift`'s membership in the SPM library target.

## Current Architecture

Glass is produced by inline Apple APIs duplicated across views. Inventory:

| API | Sites | Notes |
|---|---|---|
| `.glassEffect(.regular, in: …)` | 12 | 8 use `Theme.cardCornerRadius` (16); 1 `sessionTileCornerRadius` (8); 1 `lensCornerRadius` (28); 1 `.capsule` |
| `.buttonStyle(.glass)` | 17 | all standard `.glass`, no prominent |
| `GlassEffectContainer(spacing:)` | 4 | spacings: 12, 0, default, `Theme.cardSpacing` (16) |
| `glassEffectID("onboarding", in:)` | 4 | onboarding morph between sign-in and URL cards |

Files: `SessionView`, `OnboardingView`, `ExerciseSection`, `EmptyStateView`, `SettingsView`,
`SessionTile`, `RestPillView`, `MoveOnCelebrationView`, `DeveloperToolsView`,
`LoggedSetReviewCard`, `SmartValuePills`, `SessionProgressHeader`.

Constraint: `Package.swift` excludes `WorkoutTracker/Views/` (plus `GoogleAuth.swift` and the
app entry point) from the SPM library target, which declares iOS 18. Glass APIs require iOS 26.
`Theme.swift` is **not** excluded, so it must stay free of glass APIs. Views are therefore
verified via Xcode, not `swift test`.

## Target Architecture

One file, `WorkoutTracker/Views/WorkoutGlass.swift`, owns every Apple glass call. It lives
under `Views/` to inherit the SPM exclusion (so it may use iOS-26-only APIs). Shape radii
remain single-sourced in `Theme.swift` (iOS-18-safe `CGFloat` constants); `WorkoutGlass` maps
its surface variants to those constants. After migration, no native glass API
(`glassEffect`, `buttonStyle(.glass)`, `GlassEffectContainer`, `glassEffectID`,
`glassEffectUnion`, `glassEffectTransition`) appears anywhere outside `WorkoutGlass.swift`.

## Contracts

`WorkoutGlass` public surface — **[ADDED]**:

```swift
// Surface shape variants; radius is sourced from Theme (single source of truth)
enum GlassSurface { case card, tile, lens, capsule }
enum GlassProminence { case regular, clear }   // → Glass.regular / .clear

extension View {
    // Builds Glass = prominence → .tint(tint)? → .interactive()? then
    // .glassEffect(glass, in: shape-for-variant). Defaults reproduce every current site.
    func workoutGlass(_ surface: GlassSurface,
                      prominence: GlassProminence = .regular,
                      tint: Color? = nil,
                      interactive: Bool = false) -> some View

    func workoutGlassID(_ id: some Hashable & Sendable, in ns: Namespace.ID) -> some View
    func workoutGlassUnion(id: some Hashable & Sendable, in ns: Namespace.ID) -> some View
    func workoutGlassTransition(_ transition: GlassEffectTransition) -> some View
}

// Button styles — aliases over Apple's styles (exact type names confirmed against the SDK)
extension PrimitiveButtonStyle where Self == GlassButtonStyle {
    static var workoutGlass: Self { .glass }
}
extension PrimitiveButtonStyle where Self == GlassProminentButtonStyle {
    static var workoutGlassProminent: Self { .glassProminent }
}

// Container — wraps GlassEffectContainer; spacing defaults to the card grid spacing
struct WorkoutGlassContainer<Content: View>: View {
    var spacing: CGFloat = Theme.cardSpacing
    @ViewBuilder var content: () -> Content
    // body: GlassEffectContainer(spacing: spacing) { content() }
}
```

`Theme` constant — **[ADDED]**: `Theme.lensCornerRadius: CGFloat = 28` (promoted from the
`private static` in `MoveOnCelebrationView`; the view's non-glass `RoundedRectangle`
backgrounds also switch to it).

Surface variant → shape mapping (the only behavior the helper encodes):

| Variant | Shape |
|---|---|
| `.card` | `.rect(cornerRadius: Theme.cardCornerRadius)` |
| `.tile` | `.rect(cornerRadius: Theme.sessionTileCornerRadius)` |
| `.lens` | `.rect(cornerRadius: Theme.lensCornerRadius)` |
| `.capsule` | `.capsule` |

Call-site rewrites — **[CHANGED]** (mechanical, behavior-preserving):

| Before | After |
|---|---|
| `.glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))` | `.workoutGlass(.card)` |
| `.glassEffect(.regular, in: .rect(cornerRadius: Theme.sessionTileCornerRadius))` | `.workoutGlass(.tile)` |
| `.glassEffect(.regular, in: .rect(cornerRadius: lensCornerRadius))` | `.workoutGlass(.lens)` |
| `.glassEffect(.regular, in: .capsule)` | `.workoutGlass(.capsule)` |
| `.buttonStyle(.glass)` | `.buttonStyle(.workoutGlass)` |
| `GlassEffectContainer(spacing: X) { … }` | `WorkoutGlassContainer(spacing: X) { … }` |
| `.glassEffectID("onboarding", in: ns)` | `.workoutGlassID("onboarding", in: ns)` |

Inline native glass usage outside `WorkoutGlass.swift` — **[REMOVED]**.

## Migration Plan

Each phase is independently buildable and visually verifiable; risk decreases as raw APIs
disappear.

### Phase 1: Introduce the helper

- **Change:** Add `WorkoutGlass.swift`; promote `lensCornerRadius` to `Theme`. No call sites
  changed yet.
- **Compatibility:** Additive; existing inline glass keeps working.
- **Acceptance criteria:** Xcode build succeeds; `WorkoutGlass` covers all four categories and
  the full vocabulary; no behavioral change.

### Phase 2: Migrate call sites, file by file

- **Change:** Rewrite the 36 sites per the contract table, one view file per reviewable unit.
- **Compatibility:** Output must be pixel-identical; screenshot each migrated surface against a
  pre-migration baseline.
- **Acceptance criteria:** Per file — Xcode build green, visual parity confirmed, no remaining
  native glass APIs in that file.

### Phase 3: Close out

- **Change:** Append the dated supersession note to ADR 0004.
- **Compatibility:** Docs only.
- **Acceptance criteria:** Grep gate passes (see Deletion Criteria); ADR 0004 reflects the new
  decision.

## Deletion Criteria

Inline native glass APIs are fully retired when:

```
grep -rn "glassEffect\|buttonStyle(.glass\|GlassEffectContainer\|glassEffectID" \
  WorkoutTracker/Views | grep -v WorkoutGlass.swift
```

returns no results.

## Acceptance Criteria

- [ ] `WorkoutGlass.swift` exists under `Views/` and exposes the full vocabulary in Contracts.
- [ ] All 36 call sites across the 12 files use the helper; the grep gate above is empty.
- [ ] `Theme.lensCornerRadius` exists; `MoveOnCelebrationView` uses it for glass and non-glass.
- [ ] Xcode build succeeds for the `WorkoutTracker` scheme on iPhone 17 Pro.
- [ ] Visual parity confirmed on: SessionView cards + buttons, OnboardingView morph,
      MoveOnCelebrationView lens, RestPillView capsule, EmptyStateView, SettingsView, SessionTile.
- [ ] `WorkoutTrackerUITests` pass (excepting the known pre-existing failure
      `testIncompleteSetLogCanStillBeSkippedWithHold`).
- [ ] SwiftLint plugin and `swift-format` clean.
- [ ] ADR 0004 has the dated supersession note.

## Testing Strategy

- **Build/verify via Xcode**, not `swift test` (Views are excluded from the SPM target). Copy
  `Secrets.xcconfig` into the worktree before any `xcodebuild`.
- **Visual regression by screenshot diff** (Ralph `snapshot.sh` / XcodeBuildMCP) on each glass
  surface — this is the primary correctness check for a pure refactor.
- **Existing UI tests** as a behavioral guardrail.
- No new snapshot-testing dependency is introduced (out of scope per PR #166 Priority 3).

## Open Questions

- Exact SDK type names for the button-style aliases (`GlassButtonStyle` /
  `GlassProminentButtonStyle`) must be confirmed during implementation; if the static-alias
  form is unavailable, fall back to small wrapping `PrimitiveButtonStyle` types. This does not
  change the call-site contract (`.buttonStyle(.workoutGlass)` / `.workoutGlassProminent`).
