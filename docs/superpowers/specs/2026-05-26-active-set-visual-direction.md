# Active Set Visual Direction

**Date:** 2026-05-26
**Status:** Approved
**Supersedes:** `2026-05-25-obsidian-color-system-design.md` and the color
direction in ADR 0004.

## Source of truth

The approved visual reference is the screenshot captured on 2026-05-26 at
3:37:40 PM. It shows the Active Set Focus logging screen with a dark phone
canvas, mint/emerald accents, a soft green glass active card, and a saturated
mint primary action.

## Visual personality

The app should feel like a focused workout cockpit: dark, immediate, fresh, and
kinetic. It is still native iOS and Liquid Glass, but the color energy comes
from mint/emerald accents rather than amber, gold, or a flat obsidian void.

Avoid:

- Antique gold, amber, or burnt-orange accents.
- A near-flat black UI with only rare accent hits.
- Marketing-style decoration, large ornamental gradients, or arcade neon.
- Hiding all richness in system glass alone.

## Palette

Use these as target colors, not as a demand for pixel-perfect matching:

| Role | Approx hex | Usage |
| --- | --- | --- |
| App background | `#010806` to `#020D09` | Full-screen base behind content |
| Primary mint | `#5CE6A3` | Log button, progress fill, primary counts |
| Mint text accent | `#6FF0B5` | RPE and important active values |
| Green glass fill | `#132C22` to `#1D3D2F` | Active card body |
| Deep card fill | `#07130F` to `#10261C` | Last Performed card |
| Green stroke | `#225C42` to `#347A58` | Card and pill outlines |
| Primary text | `#F5F7F3` | Exercise name and large values |
| Muted text | `#AAB8B0` | Labels, breadcrumb, helper status |

## Hierarchy

### Session header

- Sits directly at the top of the logging screen as lightweight chrome, not as
  a floating card.
- Breadcrumb on the left, remaining-set count on the right.
- Remaining count uses primary mint.
- Progress bar is compact, low-height, and mint-filled over a dark track.
- Horizontal margins align with the Last Performed and active set cards below.
- Header should be visually quiet; the active set card owns the screen.
- Pull-revealed gear/sync actions are Session Controls. When visible, they live
  in reserved header layout space and use localized Liquid Glass treatment around
  the controls only. They should not float over workout content, obscure the
  remaining-set count, or blur the full Session header.

### Last Performed card

- Small pinned card above the active set.
- Deep green glass fill with green stroke.
- Label is muted; the Set Log is bold and high-contrast.
- Source label stays inline after the Set Log, separated with a dot.
- Static and non-tappable.

### Active set card

- Large rounded glass surface with a subtle green gradient.
- Stroke is visible enough to define the surface against the black canvas.
- Top row: muted "Up next" label and an emerald "Set N of M" badge.
- Exercise name is large, bold, and white.
- Prescription row is oversized: reps large on the left, RPE in mint on the
  right.
- The card should feel like the one place to act, not one card among many.
- Only one card should be visually in focus at a time. When a Logged or
  Unstructured Set Log is opened for review/editing, that review/edit card owns
  focus and the normal "Up next" card should visually step back until the edit
  is collapsed or saved.
- Card focus is persistent: tapping outside the focused card should not collapse
  or defocus it. Background taps may dismiss active field UI only. The focused
  card changes when the athlete logs, skips, selects another Set, or opens a
  Logged/Unstructured Set Log for review/editing.

### Smart value pills

- Three equal pills: Weight, Reps, RPE.
- Dark fill, green stroke, muted label, large white value.
- Pills are large enough for gym use and should not resemble small form fields.
- A selected or edited pill may strengthen the mint stroke, but should not
  introduce a new hue.
- Do not show a generic Cancel button in the normal logging card. Tapping
  outside a pill should dismiss only the active field UI, such as the keyboard
  or RPE picker, while the card remains the single focused card.

### Primary action

- Full-width rounded mint button near the bottom of the active card.
- Button text is dark, bold, and previews the exact Set Log.
- Use the same mint family as the progress fill.
- Skip remains a supported Set State, but should be a deliberate hold action on
  the primary button instead of a menu-first action. Pressing and holding should
  fill/progress the button, transition its label toward "Skipped", and shift the
  button color enough to signal that the athlete is about to skip; releasing
  early cancels the skip.

## Implementation notes

- `Theme.accent` should move from antique gold to the primary mint.
- Keep visual constants centralized in `WorkoutTracker/Theme.swift`.
- Keep Liquid Glass surfaces selective: Last Performed, Active Set, onboarding,
  and empty states. Compact rows should remain quieter than the active card.
- Existing issue text that references ADR 0004 should inherit the layering
  model only, not its older palette.

## Verification

For UI issues in the Active Set Focus work, visual verification should check:

- No amber, gold, or orange accent remains in the logging flow.
- The active set card has a green glass fill/stroke and dominates the screen.
- The Log button is saturated mint with dark text.
- Header progress, remaining count, RPE accent, and button all use the same
  mint family.
- Labels remain muted and readable over the dark/green surfaces.
