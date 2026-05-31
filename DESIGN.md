---
name: Workout App
description: A focused iOS training cockpit for coach-programmed powerlifting Sessions.
colors:
  background-top: "#050806"
  background-bottom: "#041C11"
  primary-mint: "#73FFB8"
  accent-ink: "#051F12"
  progress-track: "#060E0A"
  active-card-fill: "#08331F"
  active-card-stroke: "#3BD17A"
  last-performed-fill: "#081A12"
  last-performed-stroke: "#215C40"
  pill-fill: "#080F0D"
  pill-stroke: "#3DAD6B"
  session-complete: "#085229"
  text-primary: "#F5F7F3"
  text-muted: "#AAB8B0"
  skip-danger: "#FF3B30"
typography:
  display:
    fontFamily: "SF Pro, system-ui, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "34px"
    fontWeight: 900
    lineHeight: 1.08
    letterSpacing: "0"
  headline:
    fontFamily: "SF Pro, system-ui, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "17px"
    fontWeight: 700
    lineHeight: 1.25
    letterSpacing: "0"
  title:
    fontFamily: "SF Pro, system-ui, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "20px"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "0"
  body:
    fontFamily: "SF Pro, system-ui, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.35
    letterSpacing: "0"
  label:
    fontFamily: "SF Pro, system-ui, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "12px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "0"
rounded:
  progress: "3px"
  control: "8px"
  card: "16px"
  capsule: "999px"
spacing:
  xs: "8px"
  sm: "10px"
  md: "12px"
  lg: "16px"
  xl: "28px"
components:
  button-log:
    backgroundColor: "{colors.primary-mint}"
    textColor: "{colors.accent-ink}"
    typography: "{typography.headline}"
    rounded: "{rounded.control}"
    padding: "14px 16px"
  card-active-set:
    backgroundColor: "{colors.active-card-fill}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.card}"
    padding: "16px"
  card-last-performed:
    backgroundColor: "{colors.last-performed-fill}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.card}"
    padding: "12px 14px"
  pill-value:
    backgroundColor: "{colors.pill-fill}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.control}"
    padding: "12px"
  tile-session:
    backgroundColor: "{colors.progress-track}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.control}"
    padding: "12px"
---

# Design System: Workout App

## 1. Overview

**Creative North Star: "The Warm Training Cockpit"**

Workout App is a native iOS tool for a single powerlifting athlete using it between Sets on the gym floor. The visual system should feel immediate and grounded: the athlete sees the Current Session, understands the next Set, logs the exact Set Log, and returns attention to the bar.

The current implementation uses a dark green canvas with mint action states, selective Liquid Glass, and compact card hierarchy. That code is the baseline, but it is not a permanent brand constraint. Future redesign work should keep the cockpit clarity and native iOS familiarity while moving the mood closer to PRODUCT.md's "warm, focused, trustworthy" promise. Warmth comes from calm hierarchy, honest sync state, tactile controls, and earned acknowledgement, not from hype graphics or constant celebration.

The system rejects bro-y hype, spreadsheet-shaped density, generic fitness SaaS cards, and over-gamified feedback. It should feel like a supportive training partner that respects the athlete's expertise and shows real numbers plainly.

**Key Characteristics:**
- One focused action area owns the screen.
- Dark green depth is functional, never decorative.
- Mint is reserved for action, current state, and trustworthy progress.
- Liquid Glass is selective and platform-native.
- Celebration is rare and tied to Move On, not individual taps.

## 2. Colors

The palette is a restrained dark green system with a saturated mint action color. It may be redesigned later, but any replacement must preserve clear state hierarchy, high contrast, and a warmer product mood than the current intense cockpit.

### Primary
- **Primary Mint**: The main action and current-state color. Use for the Log button, progress fill, remaining count, selected values, and the Move On Celebration stamp. Keep it rare enough that it means "act here" or "this is current."
- **Accent Ink**: The text color placed on Primary Mint. Use for button text, mint badges, and checkmark marks that sit inside saturated mint.

### Secondary
- **Green Glass Fill**: The active Set surface. Use when a card owns the athlete's attention.
- **Green Stroke**: The active Set and selected-control outline. Use to define glass surfaces against the dark canvas without making every border loud.

### Tertiary
- **Skip Danger**: The hold-to-skip progress color. Use only while the athlete is actively holding to Skip or clearing logged work. It must never become a general accent.

### Neutral
- **Background Top** and **Background Bottom**: The fixed full-screen gradient behind all content.
- **Progress Track**: The dark rail for future Sets and inactive progress segments.
- **Last Performed Fill** and **Last Performed Stroke**: The quiet historical reference surface above the active Set.
- **Pill Fill** and **Pill Stroke**: The Weight, Reps, RPE, increment, and summary-chip surface vocabulary.
- **Session Complete**: The completed Session tile fill in the Block grid.
- **Primary Text**: High-contrast values, Exercise names, and major outcomes.
- **Muted Text**: Labels, source text, helper copy, and secondary metadata.

### Named Rules

**The Mint Means Current Rule.** Mint is for the next action, the current Set, selected state, or progress that has actually happened. Do not use it as decoration.

**The Warmth Without Beige Rule.** If the palette moves warmer, do it through richer state colors, calmer contrast, and friendlier spacing. Do not switch to cream, tan, or generic wellness neutrals unless the product strategy changes.

**The No Amber Regression Rule.** ADR-0004's older amber direction is superseded. Do not introduce antique gold, amber, burnt orange, or flat obsidian with rare accent hits.

## 3. Typography

**Display Font:** SF Pro, system-ui, -apple-system, BlinkMacSystemFont, sans-serif
**Body Font:** SF Pro, system-ui, -apple-system, BlinkMacSystemFont, sans-serif
**Label/Mono Font:** SF Pro, system-ui, -apple-system, BlinkMacSystemFont, sans-serif

**Character:** Typography is native, familiar, and compact. Weight carries hierarchy more than font novelty: bold values for logging, semibold labels for orientation, and plain system copy for settings and errors.

### Hierarchy
- **Display** (900, 34px, 1.08): Celebration titles and rare milestone moments only.
- **Headline** (700, 17px, 1.25): Exercise names, primary button labels, and important card values.
- **Title** (700, 20px, 1.2): Session tiles, large value pills, and compact screen-level emphasis.
- **Body** (400, 17px, 1.35): Standard settings copy, explanatory text, and editable values.
- **Label** (600, 12px, 1.2): Pill labels, breadcrumb text, badges, progress labels, and source labels. Uppercase is allowed only for short UI labels like "Up next" and Last Performed labels.

### Named Rules

**The Numbers Stay Plain Rule.** Loads, reps, RPE, Set counts, and sync state must use direct native type. Do not stylize numbers with novelty fonts, outlines, gradient text, or decorative tracking.

**The Product Scale Rule.** Use fixed native type sizes. Do not introduce fluid display typography into the app UI.

## 4. Elevation

Workout App uses tonal layering, strokes, and selective Liquid Glass instead of a broad shadow system. Depth is created by a full-screen dark gradient, glass surfaces for high-value containers, quiet dark fills for controls, and 1px strokes that define tappable regions. Shadows are exceptional: the current code uses a mint glow for the Move On Celebration stamp and a stronger active Exercise focus glow, not for ordinary cards.

### Shadow Vocabulary
- **Celebration Glow**: A soft mint glow under the Move On Celebration stamp. Use only for earned celebration.
- **Active Focus Glow**: A mint glow used when an Exercise section is actively focused. Use sparingly; if every card glows, none is focused.

### Named Rules

**The Glass Has a Job Rule.** Glass belongs on active Exercise cards, Last Performed, onboarding, empty states, Session Controls, and system button affordances. Do not apply glass everywhere.

**The Flat At Rest Rule.** Ordinary rows, pills, and tiles are flat at rest. Use fill, stroke, and type hierarchy before adding shadow.

## 5. Components

### Buttons
- **Shape:** Gently squared native controls (8px radius) for logging, capsules for icon-only Session Controls.
- **Primary:** Full-width mint Log button with dark text, bold headline type, and 14px vertical padding. The label previews the exact Set Log the athlete is about to write.
- **Hover / Focus:** Native iOS state feedback. During hold-to-skip, the button fills with Skip Danger and reveals a Skip affordance after the configured delay.
- **Secondary / Ghost / Tertiary:** Use `.buttonStyle(.glass)` for Settings, Sync, Move On, and contextual actions. Use `.buttonStyle(.plain)` only when the surface itself already carries the affordance.

### Chips
- **Style:** Dark green fill, green stroke, semibold muted label, bold white value.
- **State:** Selected or invalid states strengthen the stroke. Invalid fields use red stroke only on the specific bad field. Chips stay large enough for gym use and must not collapse into tiny form fields.

### Cards / Containers
- **Corner Style:** Cards use 16px radius. Tiles and pills use 8px radius. Do not exceed these values for rectangular app surfaces.
- **Background:** Active Set cards use Green Glass Fill; Last Performed cards use the quieter historical fill; value pills use Pill Fill.
- **Shadow Strategy:** Use tonal layering, strokes, and Liquid Glass before shadows.
- **Border:** Use 1px strokes for cards and pills; the active/current item may use stronger mint or Green Stroke.
- **Internal Padding:** Cards default to 16px. Last Performed uses 14px horizontal and 12px vertical. Value pills use 12px horizontal padding.

### Inputs / Fields
- **Style:** Weight and Reps edit in-place inside the value pill, preserving the same pill frame.
- **Focus:** Tapping a pill focuses only that field. Tapping outside dismisses field UI, not the active card.
- **Error / Disabled:** Invalid fields use a 2px red stroke. Disabled states reduce opacity rather than changing hue families.

### Navigation
- **Style:** Standard `NavigationStack` and platform chrome. The Session header is lightweight chrome, not a floating card.
- **Active State:** Remaining Set count and current progress use Primary Mint. The progress rail is compact, dark, and segmented.
- **Mobile Treatment:** This is an iPhone-first layout. Header controls reveal in reserved top space and must not obscure workout content.

### Active Set Card

The Active Set Card is the signature component. It contains the "Up next" label, Set ordinal badge, Exercise name, Weight/Reps/RPE pills, and the Log button. It should feel like the one place to act, not one card among many.

### Last Performed Card

Last Performed is a quiet reference card above the active Set. It is static, non-tappable, and visually subordinate to the Active Set Card.

### Move On Celebration

Move On Celebration is the only large celebratory moment. It can use heavy type, ripples, haptics, and the mint stamp because it marks a real Session transition.

## 6. Do's and Don'ts

### Do:
- **Do** keep coach-authored spreadsheet structure hidden behind Sessions, Exercises, Sets, and Set Logs.
- **Do** make the next logging action obvious and reachable with one hand.
- **Do** show sync and pending-write state honestly. Never imply a Set Log has landed if it has not.
- **Do** use Primary Mint for current, active, and completed progress states that are real.
- **Do** keep Liquid Glass selective so important workout surfaces keep their weight.
- **Do** use exact domain language from CONTEXT.md: Block, Week, Session, Exercise, Set, Set Log, Last Performed, Move On.
- **Do** preserve native iOS affordances for Settings, Sync, sheets, navigation, and text input.
- **Do** keep celebration tied to Move On and genuine Session progress.

### Don't:
- **Don't** use **Bro-y hype / aggro fitness** styling: no beast-mode copy, flames, neon-on-black aggression, or all-caps shouting.
- **Don't** make a **Spreadsheet-in-an-app** UI: no raw cell editing, dense grids, tiny tap targets, or visible row and column plumbing.
- **Don't** use **Generic fitness SaaS** patterns: no interchangeable rounded-card dashboards, stock gradients, badge spam, ring charts everywhere, or cheerful clip art.
- **Don't** over-gamify: no XP bars, points, levels, streak pressure, mascots, or confetti on normal logging taps.
- **Don't** use amber, gold, burnt orange, or the superseded warm-amber palette from ADR-0004.
- **Don't** use gradient text, side-stripe borders, broad decorative glass, or repeated identical card grids.
- **Don't** add decorative motion. Motion must convey state: logging, focusing, skipping, syncing, or moving on.
- **Don't** introduce cards inside cards. Surfaces can be stacked, but each layer must have a distinct job.
- **Don't** exceed 16px radius on rectangular cards or 8px on tiles and value pills.
- **Don't** use "workout", "training day", "lift", "working set", "actual load", or "Finish Session" where the domain glossary says to use Session, Exercise, Set, Set Log, or Move On.
