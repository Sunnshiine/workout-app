# Rest Timer UI Design Spec

## Goal

Define the Rest pill as an ambient bottom Liquid Glass capsule shown while a Rest runs. It is a
glanceable timer, not a destination, screen, toolbar, or celebration.

## Rest Pill Contract

- The pill renders in `SessionView`'s bottom safe-area inset so it reserves space and does not cover
  the Log button, Move On, or active Set controls.
- The capsule is centered and uses a fixed width near 40% of the available screen width. It should
  feel compact and intentional in both Dark and Sage Light, not like a content-hugging banner.
- The pill remains a Liquid Glass capsule. If the WorkoutGlass primitive has landed, use
  `.workoutGlass(.capsule)`; otherwise keep the existing inline `.glassEffect(.regular, in: .capsule)`.
- The visible anatomy is only the `mm:ss` countdown and a thin bottom hairline. There is no visible
  `Rest` or `Superset rest` label.
- The pill is non-dismissible. It has no `xmark`, no manual clear button, no whole-pill dismiss tap,
  and no swipe-to-dismiss affordance. Rest clears only from model events: expiry, logging the next
  Set, Move On, or deleting the origin Set Log.
- The spoken VoiceOver label keeps the rest type and remaining time, for example
  `Rest, 1 minute 23 seconds remaining` or `Superset rest, 30 seconds remaining`.
- The countdown uses plain native numeric type, bold, monospaced digits, and updates once per
  displayed second.
- The hairline depletes from full to empty across the whole Rest. It must move smoothly and
  continuously, not in one-second steps, while the digits keep normal second ticks.
- The final-five-seconds cue may intensify the existing accent color and pulse the countdown when
  Reduce Motion is off. It must not flash red, feel like an alarm, or add celebration.

## Dark And Sage Light

The pill reads from the current `Theme.Palette`: `palette.pillFill`, `palette.pillStroke`,
`palette.valueText`, and `palette.accent`. No hard-coded mode-specific colors are introduced.
Dark keeps the deep green cockpit treatment. Sage Light keeps the softer sage-cream surface with
grounded green accent.

## Accessibility

- The countdown text is hidden from accessibility so VoiceOver reads the combined pill label once.
- The accessibility label includes rest type plus remaining time even though the visual type label
  is removed.
- Reduced Motion keeps opacity/tint changes and skips repeated scale breathing.
- Dynamic Type must not make the number overflow the capsule; use one line and a conservative
  minimum scale factor.

## Accepted Deviations

- The previous dismiss affordance is intentionally removed. This supersedes PRD #156's one-tap
  dismiss story.
- The previous visible `Rest` / `Superset rest` label is intentionally removed. Superset Rest has no
  separate visual distinguisher beyond the shorter duration.
- The hairline direction is depleting, full to empty, and the motion is continuous.

## Acceptance Criteria

- [ ] Pill renders at fixed roughly 40% screen width and is centered in Dark and Sage Light.
- [ ] No `xmark` or manual dismiss control exists in the view.
- [ ] No `Rest` or `Superset rest` text is visible.
- [ ] VoiceOver still announces rest type and remaining time.
- [ ] Hairline animates smoothly full to empty without visible per-second stepping.
- [ ] Countdown digits keep ticking once per displayed second.
