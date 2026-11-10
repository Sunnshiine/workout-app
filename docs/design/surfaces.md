# Surfaces, elevation, and radius

The elevation scale, the radius family, and the surface Named Rules for [DESIGN.md](../../DESIGN.md) §4.

## Elevation scale

Five levels, lowest first. Each is a `Theme.BoxShadow` recipe in the token sheet, drawn through
`themeElevation`. A surface takes the level of what it is, never a one-off shadow.

| Level | Who sits there | Day | Night |
| --- | --- | --- | --- |
| Carved | History chips, the pressed volume control | inset shade + light lip | same recipe, night values |
| Flat | Rails, tiles, chips at rest | fill only | fill only |
| Raised control | Steppers, queue pill, the queue sheet's header button, the countdown pill, the volume control | 1px ink edge @ 8% + `cardLow` | 1px cream ring @ 14% |
| Card in shade | Collapsed week cards, Sheet tab Day cards | 1px ink edge @ 6% + `cardLow` | 1px cream ring @ 10% |
| Lifted card | Active Set Card, ceremony stats, Settings confirmation card | 1px ink edge @ 5% + crisp and wide drops | 1px cream ring @ 10% |

Three named lights sit outside the scale: the Log capsule's light, the focus card's sun halo (at
Night, a cream ring @ 14%, brighter than the week cards' edge), and the current tile's glow. A
halo's reach is part of its card's footprint, so neighbours keep their spacing from the light.

## Radius family

Every corner comes from the named family in token sheet §6, plus `hairline 2–3`. Sheets take the
system's own corners.

## Named Rules

**The Edge Is Light Rule.** A raised surface (a card, a container, a control you press) shows its
edge with a translucent 1px ring from its elevation level, never a solid stroke. Day rings are ink
at low opacity, so one token sits right on every wash; Night collapses every drop to one cream ring,
because a drop shadow vanishes on deep sage. Real strokes stay where they separate or state: text
field edges, the selected rail chip's ring, tile state outlines, the dashed empty bed, and the
logged-Set and dictation capsules. (Supersedes "at rest, pills, rails, tiles, and chips are quiet
cream fills with 1px strokes" for raised controls. Operator brief 2026-10-31: "Where Emil's
recommendation conflicts with an existing rule in DESIGN.md … Emil wins.")

**The Concentric Corner Rule.** A container whose corner holds a rounded child takes that child's
radius plus the inset between them, so the two curves run parallel. The container grows to meet the
child; the child keeps its shape. The Active Set Card is 43 (the Log capsule's ≈29 half-height plus
the 14 bottom inset) and the focus card is 31 (tile 15 plus 16). A container with no child in its
corner picks its radius on its own merits. (Supersedes the One Soft Container Rule's claim on the
Active Set Card and sheet shoulders. Operator brief 2026-10-31, as above.)

**The No Nested Cards Rule.** No cards inside cards; each layer has a distinct job.

**The History Is Carved Rule.** Below-flat elevation exists only in the Exercise History sheet's
chips and in the pressed volume control, which borrows the chips' recipe. Everything else sits on or
above the paper.
