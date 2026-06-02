# Rest Timer UI Design Spec

## Goal

Define the visual and interaction design for the two Rest Timer surfaces so a later
implementation issue can build them without reopening design questions:

1. **The Rest pill**: an ambient bottom Liquid Glass capsule shown while a Rest runs.
   Countdown plus dismiss only. Never a destination, tab, or screen.
2. **The Rest section in Settings**: two duration steppers (Standard, Superset) with
   `-/+` 30s controls.

This spec covers anatomy, tokens, layout, states, motion, copy, and accessibility. It does
**not** define the Rest store, deadline model, haptics, or notification scheduling. Those are
settled in [ADR 0007](../adr/0007-rest-timer-alerting-and-resilience.md) and the PRD
([#156](https://github.com/Sunnshiine/workout-app/issues/156)).

## Background

The athlete uses the app on the gym floor, between Sets, hands chalky, attention on the bar.
[CONTEXT.md](../../CONTEXT.md) defines a **Rest** as a countdown the app starts automatically the
moment the athlete records an intentional Set Log, pacing recovery before the next Set. At most
one Rest exists at a time; recording another Set Log restarts it. The Rest never blocks: the
athlete may keep logging, Move On, or do nothing while it runs. **Rest Duration** has two values:
the **Standard Rest Duration** (default 2:00) for an ordinary Set Log, and the shorter **Superset
Rest Duration** (default 0:30) for a Set logged in an Exercise that belongs to a Superset.

[PRODUCT.md](../../PRODUCT.md) sets the voice: a supportive training partner, not a hype machine.
Warm, focused, trustworthy. Celebration is earned and occasional, tied to Move On, never sprinkled
on individual logging. Resting is not an achievement and must not be gamified.

[DESIGN.md](../../DESIGN.md) (Warm Training Cockpit, [ADR 0004](../adr/0004-liquid-glass-design-system.md))
sets the system: selective Liquid Glass, the *Mint Means Current* rule (accent green is reserved
for the current, active, selected, or real progress), the *Numbers Stay Plain* rule (loads, reps,
counts, and time use direct native type with no novelty styling), red reserved for Skip and danger,
and no ring charts, badge spam, or decorative motion.

[ADR 0007](../adr/0007-rest-timer-alerting-and-resilience.md) settles the runtime model this UI
renders on top of: a Rest is timed by an absolute deadline `Date`, the live countdown is always
`deadline - now`, and the alerting and resilience behavior (foreground Core Haptics ramp, local
notification fallback, no persistence) is out of scope for this spec. The design only consumes the
deadline to render the countdown and mirrors the final-five-seconds haptic ramp visually.

## Design principles for these surfaces

- **Ambient, never blocking.** The pill floats over scroll content. It is reserved space in the
  bottom safe area, so it never occludes the Log button, Move On, or the active card. The athlete
  can ignore it completely.
- **Glanceable in one read.** The remaining time is the one thing the eye needs. Everything else
  is quiet around it.
- **Warm, not aggro.** The final-five-seconds urgency cue intensifies the existing accent green, it
  never flashes red, shouts, or counts down with alarm styling. Red stays reserved for Skip.
- **Earned restraint.** No celebration, no streak, no reward tied to resting. A Rest ending is a
  cue to lift, not a moment.
- **Reuse the cockpit vocabulary.** The pill and steppers are built from existing glass, pill,
  stepper, and progress-rail treatments, not new component families.

## Scope

### In

- Rest pill anatomy, layout, placement, sizing, color, and type.
- Rest pill states: running, final five seconds, expiry handoff, restart, dismissing, superset
  variant, reduced motion, accessibility.
- Rest pill motion: entry, per-second tick during the final five seconds, restart beat, exit.
- Settings Rest section: placement, anatomy, stepper styling, value format, range and step,
  disabled-at-bounds states, accessibility.
- Copy for both surfaces.
- A token map to `WorkoutTracker/Theme.swift` and the existing components each treatment reuses.
- Code-grounding notes for where each surface plugs in (no implementation).

### Out

- The Rest store, deadline model, restart and cancellation logic, and in-memory lifecycle.
- Core Haptics ramp, the extended end buzz, notification scheduling, authorization, and the
  foreground-versus-background alert decision. All settled in ADR 0007.
- Persistence of an active Rest.
- AlarmKit, ActivityKit Live Activities, and Dynamic Island presence (deferred per ADR 0007).
- Any change to Set Log writing, sync, the session HUD, or Settings rows other than the new Rest
  section.
- Live `+/-` adjustment on the running pill. Duration is changed only in Settings.

## Surface 1: The Rest pill

### Placement and container

The pill lives in `WorkoutTracker/Views/SessionView.swift` as a new `.safeAreaInset(edge: .bottom)`
on the session scroll view, paired with the existing `.safeAreaInset(edge: .top)` that renders
`sessionHeaderHUD`. Using the bottom safe-area inset is deliberate: the inset reserves vertical
space, so the scroll content insets upward to clear the pill and the pill never covers the Log
button or Move On. It floats above the home indicator automatically.

The planned view module is `RestPillView` (named in the PRD). It is rendered only while a Rest is
active; when no Rest runs, the inset is empty and contributes no space.

The container is a **capsule**, not the rectangular HUD card, so it reads as a distinct ambient
object rather than a second toolbar:

```
.glassEffect(.regular, in: .capsule)
```

It is centered, hugs its content width (with a sensible minimum), sits inside the standard
`.padding(.horizontal)` screen margin, and has roughly 8pt of breathing room above the home
indicator inside the inset.

If the pill should ever participate in a morph from the just-logged set card (see Open Questions),
it would join the session `GlassEffectContainer`. The baseline design does **not** require that; the
pill is a self-contained glass object.

### Anatomy

```
            ┌──────────────────────────────────────────────┐
            │                                              │
            │   Rest            1:23                  ✕     │
            │   └ label         └ countdown (hero)    └ dismiss
            │  ────────────────────────────────────────    │  ← depleting hairline
            └──────────────────────────────────────────────┘
                         (centered glass capsule)
```

A horizontal `HStack` inside the capsule, with a thin depleting progress hairline pinned just
inside the bottom edge:

| Element | Role | Treatment |
| --- | --- | --- |
| **Label** (leading) | Names the rest type. `Rest` or `Superset rest`. | Caption, semibold, `.secondary`. The only element that distinguishes a Superset Rest. |
| **Countdown** (center, hero) | `mm:ss` remaining, the one glanceable value. | `.title2`/`.title3` weight bold, `.monospacedDigit()`, `palette.valueText`. Largest element. |
| **Dismiss** (trailing) | Ends the Rest. | SF Symbol `xmark`, inside a 44x44pt hit target, `.secondary` foreground. |
| **Hairline** (bottom inset) | Depleting progress. | `RoundedRectangle(cornerRadius: 3)`, height ~3pt, `palette.accent`, spanning the capsule inner width. Reuses the `SessionProgressHeader` rail vocabulary at a thinner scale. |

Notes:

- **No `+/-` on the pill.** Duration changes only in Settings (hard constraint).
- **No exercise or set name on the pill** (hard constraint).
- **Countdown derives from the deadline**: `deadline - now`, rendered `mm:ss` with no leading-zero
  minute (`0:45`, `1:23`, `2:00`, `10:00`). `.monospacedDigit()` keeps the digits from shifting
  width as they tick.
- The hairline represents elapsed-versus-remaining. It depletes from full to empty as the Rest
  runs (scale on the x axis, anchored leading, mirroring the Skip progress fill technique in
  `HoldToSkipLogButton`). It is decorative reinforcement, not the primary read; the number is.

### Sizing

- Capsule min height ~52pt (comfortable thumb reach, not a bulky bar).
- Internal padding ~16pt horizontal, ~10pt vertical.
- `HStack` spacing ~14pt between label, countdown, and dismiss.
- Dismiss hit target 44x44pt (the glyph is smaller; the tappable area is full size).

### States

| State | What the athlete sees and feels |
| --- | --- |
| **Running** (default) | Capsule visible, `Rest` label, `mm:ss` ticking down, hairline depleting in quiet accent. Calm, peripheral. |
| **Superset Rest** | Identical to running, except the label reads `Superset rest`. The shorter duration is self-evident from the number; no other distinction (KISS). |
| **Final five seconds** | The countdown gently breathes once per second in sync with the haptic taps, and the digits plus hairline shift from quiet accent to full accent. Warm intensification, never red, never an alarm. |
| **Expiry handoff (0:00)** | The countdown settles at `0:00` at full accent for the brief end-buzz beat, then the pill exits. (The buzz itself and the foreground-versus-notification decision are ADR 0007.) |
| **Restart** (new Set Log) | The same pill persists. Digits cross-fade to the new duration, the hairline snaps back to full and resumes, and the glass gives one subtle pulse. It reads as "reset," not as a new object appearing. If the rest type changed, the label cross-fades too. |
| **Dismissing** | On `✕`, on origin Set Log deletion, or on Move On out of the session, the pill fades and drops away. |
| **Reduced motion** | Entry, restart, and exit become opacity-only crossfades. No per-second breath; the final-five-seconds cue collapses to a single tint shift at the 5s mark. |

The pill has no empty, loading, or error state of its own: it exists only when a Rest is active,
and the Rest model is purely local and synchronous against a deadline (ADR 0007).

### Motion

All durations and curves are drawn from the app's existing motion vocabulary in `Theme.swift`
(`focusMorphDuration` 0.28, `pairingConfirmationDuration` 0.22, `exerciseCompletionBeatDuration`
0.2, `holdToSkipTapMaximumDuration` 0.18) and `product.md` guidance (150-250ms for product
transitions). Motion conveys state; nothing here is decorative.

| Transition | Default treatment | Reduced motion |
| --- | --- | --- |
| **Entry** | Rise plus glass materialize: offset y +16 to 0, scale 0.92 to 1.0, opacity 0 to 1.0, ~0.28s, ease-out settle curve (`timingCurve(0.2, 0, 0.12, 1.0)`, the app's drop curve). | Opacity 0 to 1.0, ~0.18s. |
| **Per-second tick (last 5s)** | Countdown scale 1.0 to 1.04 to 1.0, ~0.18s ease-out, fired on each of the final five seconds, synced to the haptic taps. | Omitted. |
| **Final-5s tint** | Digits and hairline interpolate `palette.accent.opacity(0.55)` to `palette.accent` across the last five seconds, ease-in-out. | Single instant shift to full accent at the 5s mark. |
| **Restart beat** | Digits via `.contentTransition(.numericText())`; hairline resets to full over ~0.22s ease-out; capsule pulse scale 1.0 to 1.02 to 1.0 over ~0.22s. | Instant digit swap; hairline resets instantly. |
| **Exit** | Fade plus drop: offset y 0 to +12, scale 1.0 to 0.96, opacity to 0, ~0.2s ease-out. | Opacity to 0, ~0.18s. |

Suggested new `Theme` constants, grounded in the existing values, that the implementation would add:
`restPillEntryDuration` (0.28), `restPillExitDuration` (0.2), `restPillTickDuration` (0.18),
`restPillRestartDuration` (0.22), `restPillUrgencyWindow` (5 seconds).

### Accessibility

- **VoiceOver.** The pill is one element labeled with the remaining time, for example
  `Rest, 1 minute 23 seconds remaining` (and `Superset rest, ...` for the variant). The dismiss
  control is a separate button labeled `Dismiss rest`.
- **Dynamic Type.** The countdown scales with the user's text size; the capsule grows with it.
  Apply `minimumScaleFactor(0.8)` and `lineLimit(1)` on the countdown so very large sizes do not
  overflow the capsule, matching the value-field handling in `SmartValuePills`.
- **Contrast.** The countdown uses `palette.valueText` (white on dark, `.primary` on Sage Light),
  which clears 4.5:1 comfortably on the glass. The `.secondary` label and `xmark` are small; verify
  they hit 4.5:1 on the glass material during screenshot review, and bump toward `valueText` if the
  label reads washed out (per the impeccable color rule on muted text over tinted surfaces).
- **Hit target.** Dismiss is a full 44x44pt target.
- **Reduced motion** is honored as specified above; `@Environment(\.accessibilityReduceMotion)`.

## Surface 2: Settings, Rest section

### Placement

A new **Rest** section in `WorkoutTracker/Views/SettingsView.swift`. To honor the DESIGN rule that
*Settings groups use a single glass container, not nested cards*, the two rows render inside a glass
container using the same inline-header pattern as the existing Appearance block (a semibold section
label above its controls). It may sit in the existing settings glass card (separated by the standard
divider) or as its own `.glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))`
group within the `GlassEffectContainer`; either keeps the single-container rule intact.

The section is always present. There is no master toggle: the feature is always on (hard
constraint), so a toggle would imply an off state that does not exist.

### Anatomy

```
  Rest                                        ← section header (semibold)
  ┌──────────────────────────────────────────────┐
  │ ⧖  Standard rest          (−)  2:00  (+)      │
  │    After most sets                            │
  │ ────────────────────────────────────────     │
  │ ⧗  Superset rest          (−)  0:30  (+)      │
  │    After superset sets                        │
  └──────────────────────────────────────────────┘
```

Each row is a duration-stepper variant of the existing `SettingsRow` layout (icon, title, optional
detail, trailing control), with the trailing chevron replaced by a stepper control group:

| Element | Treatment |
| --- | --- |
| **Icon** | SF Symbol, `palette.accent`, 30pt frame, matching `SettingsRow`. Suggested: `hourglass` for Standard, `hourglass.bottomhalf.filled` for Superset (a more-drained glass reads as the shorter rest). Fall back to `hourglass` for both if the second symbol does not render. |
| **Title** | `.body.weight(.semibold)`, `.primary`. `Standard rest` / `Superset rest`. |
| **Detail** | `.subheadline`, `.secondary`. `After most sets` / `After superset sets`. |
| **Stepper group** (trailing) | `(−)  value  (+)`. |

### Stepper styling

Reuse the circular stepper buttons from `SmartValuePills.stepperButton`:

- `minus` / `plus` SF Symbols, `.headline.weight(.bold)`, `palette.accent` foreground,
  `palette.pillFill` background, `.capsule`, 36x36pt.
- The value sits between the two buttons: `mm:ss` (`0:30`, `2:00`, `10:00`), `.monospacedDigit()`,
  value weight, `palette.valueText`, with a fixed minimum width so the buttons do not shift as the
  value changes.

### Behavior, range, and bounds

- **Step:** 30 seconds per tap.
- **Range:** 0:30 to 10:00 inclusive.
- **Defaults:** Standard 2:00, Superset 0:30.
- **At the floor (0:30):** the `−` button is disabled and dimmed using the app's disabled pattern
  (`.disabled(true)` plus `.opacity(0.6)`, as used on the settings sync and sheet rows).
- **At the ceiling (10:00):** the `+` button is disabled and dimmed the same way.
- Changes take effect immediately and persist (persistence mechanism is the implementation's
  concern, not this spec). A duration change does not retroactively alter a Rest already running;
  the next started Rest uses the new value.

### States

| State | Treatment |
| --- | --- |
| **Default** | Both rows at their stored values, both buttons enabled (unless at a bound). |
| **At floor** | `−` disabled and dimmed on that row. |
| **At ceiling** | `+` disabled and dimmed on that row. |

No loading or error state: durations are local preferences with a fixed, validated range.

### Accessibility

- Each row is an **adjustable** element (`.accessibilityElement(children: .ignore)` with
  `accessibilityAddTraits(.isAdjustable)` and an `accessibilityAdjustableAction`) so VoiceOver users
  change the value by swiping up and down in 30s steps, the native iOS stepper pattern.
- `accessibilityLabel` is the title (`Standard rest`); `accessibilityValue` is the spoken duration
  (`2 minutes`, `30 seconds`, `10 minutes`).
- At a bound, the adjustable action in the disabled direction is a no-op; the buttons also reflect
  the disabled state visually.

## Copy

All user-facing strings, kept specific and plain (no buzzwords, no em dashes):

| Location | String |
| --- | --- |
| Pill label, standard | `Rest` |
| Pill label, superset | `Superset rest` |
| Pill dismiss, accessibility | `Dismiss rest` |
| Pill, accessibility label | `Rest, {m} minutes {s} seconds remaining` (drop the minutes clause below 1:00) |
| Settings section header | `Rest` |
| Standard row title / detail | `Standard rest` / `After most sets` |
| Superset row title / detail | `Superset rest` / `After superset sets` |
| Stepper, accessibility value | `{n} minutes` / `{n} seconds` |

Optional one-line section footnote, if the section reads as needing context:
`A countdown starts after each logged set.` Omit if the rows read clearly on their own; the product
respects the athlete's expertise and avoids over-explaining.

## Design token map

Every visual choice maps to an existing `WorkoutTracker/Theme.swift` token or an existing component
treatment, so the build introduces no new color or radius vocabulary:

| Design choice | Token / source |
| --- | --- |
| Pill glass | `.glassEffect(.regular, in: .capsule)` (matches the HUD's `.glassEffect(.regular, in:)`) |
| Countdown color | `palette.valueText` |
| Label, dismiss color | `.secondary` (verify contrast on glass) |
| Hairline, accent ticks, urgency tint | `palette.accent` (Mint Means Current) |
| Hairline shape | `RoundedRectangle(cornerRadius: 3)`, from `SessionProgressSegment` |
| Stepper buttons | `palette.accent` icon on `palette.pillFill` capsule, 36pt, from `SmartValuePills.stepperButton` |
| Stepper value color | `palette.valueText` |
| Settings group glass | `.glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))`, from `SettingsView` |
| Settings row icon color | `palette.accent`, from `SettingsRow` |
| Disabled-at-bound | `.disabled(true)` + `.opacity(0.6)`, from `SettingsView` rows |
| Card corner radius | `Theme.cardCornerRadius` (16) |
| Motion durations | `Theme.focusMorphDuration` 0.28, `pairingConfirmationDuration` 0.22, `holdToSkipTapMaximumDuration` 0.18, plus suggested `restPill*` constants |

Both appearances (Dark and Sage Light) inherit automatically because every value reads from
`palette` rather than hard-coded color.

## Where it plugs in (code-grounding, not implementation)

- **`WorkoutTracker/Views/SessionView.swift`**: add `.safeAreaInset(edge: .bottom)` rendering
  `RestPillView` when a Rest is active, alongside the existing `.safeAreaInset(edge: .top)` HUD
  (around lines 86 to 88). Scroll content is the `GlassEffectContainer` (around lines 40 to 82).
- **`WorkoutTracker/Views/SettingsView.swift`**: add the Rest section inside the existing
  `GlassEffectContainer`, following the Appearance block pattern.
- **New module**: `RestPillView` (per the PRD), a presentation-only view driven by the Rest model
  from ADR 0007 and the PRD; it owns no timing or alert logic.
- **Visual vocabulary reused**: `SmartValuePills` (`PillChrome`, `stepperButton`),
  `SessionProgressHeader` (segmented rail), `SettingsView` (`SettingsRow`, glass container).

## Open questions and accepted deviations

- **Morph from the just-logged set card.** The handoff invites considering a GlassEffect morph from
  the set card the athlete just logged into the pill. This is genuinely fiddly across the
  `safeAreaInset` seam (the card lives inside the scroll `GlassEffectContainer`; the pill lives in
  the bottom inset, a different container), so the baseline is the simpler rise-and-materialize
  entry. The morph is recorded as a **stretch enhancement** to attempt during visual iteration, not
  a baseline commitment. Accepted deviation from the handoff prompt: baseline ships without it.
- **Pill label presence.** The baseline keeps a quiet `Rest` / `Superset rest` label as the
  superset differentiator. An even more minimal label-less variant (countdown plus dismiss only,
  superset distinguished only by the shorter number) is a reasonable alternative if screenshot
  review finds the label adds noise. The label is the recommended default because it gives a clean,
  honest slot for the superset distinction using exact domain language.
- **Hairline direction.** Baseline depletes (full to empty) to read as time draining. A filling
  variant (empty to full) is the alternative; deplete is recommended because "less bar" maps to
  "less rest left."

## Acceptance criteria

- [ ] The spec exists at `docs/specs/2026-06-01-rest-timer-ui-design.md`.
- [ ] The pill is specified as a bottom safe-area Liquid Glass capsule with countdown plus dismiss
      only, no `+/-`, and no exercise or set name.
- [ ] The pill is non-blocking: the bottom inset reserves space so it never occludes the Log button
      or Move On.
- [ ] The countdown is `mm:ss`, `.monospacedDigit()`, `palette.valueText`, derived from the deadline.
- [ ] Progress is a thin depleting accent hairline reusing the session rail vocabulary, not a ring.
- [ ] The final-five-seconds cue is specified as warm accent intensification plus a per-second
      breath synced to the haptic taps, never red, never an alarm, with a reduced-motion fallback.
- [ ] The Superset Rest is distinguished only by the `Superset rest` label; pill form is identical.
- [ ] Dismiss is an explicit `✕` with a 44pt target; no whole-pill tap and no swipe dismissal.
- [ ] Entry, restart, and exit motion are specified with durations, curves, and reduced-motion
      fallbacks, drawn from the existing `Theme` motion vocabulary.
- [ ] The Settings Rest section is specified: two adjustable rows, `-/+` 30s steppers reusing the
      `SmartValuePills` stepper buttons, range 0:30 to 10:00, defaults 2:00 and 0:30, disabled at
      bounds, always-on with no master toggle.
- [ ] Every color and radius maps to an existing `Theme.swift` token; both Dark and Sage Light are
      covered by reading from `palette`.
- [ ] All user-facing copy is listed, with no buzzwords and no em dashes.
- [ ] Accessibility is specified for both surfaces: VoiceOver labels, Dynamic Type, contrast,
      44pt targets, adjustable steppers, reduced motion.
- [ ] No alerting, notification, persistence, or store behavior is redefined; ADR 0007 stays
      authoritative.

## Validation note

This spec is design-only; no Swift was written. Final visual finish (glass material read, contrast
of the muted label on glass, motion timing feel, Dynamic Type at large sizes) belongs to a
screenshot-review QA pass on a seeded `SessionView` fixture once `RestPillView` is implemented, per
the project's screenshot-review mandate. Deterministic pill states (running, final five seconds,
superset, restart, expiry) and Settings bound states should be exposed as fixtures for that pass.

## Open Questions

None blocking. The three items under "Open questions and accepted deviations" record recommended
defaults with named alternatives to revisit during screenshot review; they do not block
implementation.
