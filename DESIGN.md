---
name: Workout App
description: A focused iOS training cockpit for coach-programmed powerlifting Sessions.
colors:
  dark-background-top: "#050806"
  dark-background-bottom: "#041C11"
  dark-primary-mint: "#73FFB8"
  dark-accent-ink: "#051F12"
  dark-progress-track: "#060E0A"
  dark-active-card-fill: "#08331F"
  dark-active-card-stroke: "#3BD17A"
  dark-last-performed-fill: "#081A12"
  dark-last-performed-stroke: "#215C40"
  dark-pill-fill: "#080F0D"
  dark-pill-stroke: "#3DAD6B"
  dark-session-complete: "#085229"
  sage-background-top: "#E8EDDB"
  sage-background-bottom: "#C7E0BF"
  sage-primary-green: "#0D6B40"
  sage-accent-cream: "#F2F7E8"
  sage-progress-track: "#B3C7AD"
  sage-active-card-fill: "#E0EDD6"
  sage-active-card-stroke: "#1F8552"
  sage-last-performed-fill: "#D1E3CC"
  sage-last-performed-stroke: "#528C66"
  sage-pill-fill: "#F2F6E8"
  sage-pill-stroke: "#75A887"
  sage-session-complete: "#0F6138"
  sage-session-incomplete: "#E8F0DE"
  sage-session-unavailable: "#D1DEC7"
  text-primary-dark: "#F5F7F3"
  text-muted-dark: "#AAB8B0"
  text-primary-light: "#152118"
  text-muted-light: "#526457"
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
  button-log-dark:
    backgroundColor: "{colors.dark-primary-mint}"
    textColor: "{colors.dark-accent-ink}"
    typography: "{typography.headline}"
    rounded: "{rounded.control}"
    padding: "14px 16px"
  button-log-light:
    backgroundColor: "{colors.sage-primary-green}"
    textColor: "{colors.sage-accent-cream}"
    typography: "{typography.headline}"
    rounded: "{rounded.control}"
    padding: "14px 16px"
  card-active-set-dark:
    backgroundColor: "{colors.dark-active-card-fill}"
    textColor: "{colors.text-primary-dark}"
    rounded: "{rounded.card}"
    padding: "16px"
  card-active-set-light:
    backgroundColor: "{colors.sage-active-card-fill}"
    textColor: "{colors.text-primary-light}"
    rounded: "{rounded.card}"
    padding: "16px"
  pill-value-dark:
    backgroundColor: "{colors.dark-pill-fill}"
    textColor: "{colors.text-primary-dark}"
    rounded: "{rounded.control}"
    padding: "12px"
  pill-value-light:
    backgroundColor: "{colors.sage-pill-fill}"
    textColor: "{colors.text-primary-light}"
    rounded: "{rounded.control}"
    padding: "12px"
  tile-session:
    backgroundColor: "{colors.dark-progress-track}"
    textColor: "{colors.text-primary-dark}"
    rounded: "{rounded.control}"
    padding: "12px"
  banner-sync:
    backgroundColor: "{colors.dark-pill-fill}"
    textColor: "{colors.text-primary-dark}"
    rounded: "{rounded.capsule}"
    padding: "8px 12px"
  settings-row:
    backgroundColor: "{colors.dark-pill-fill}"
    textColor: "{colors.text-primary-dark}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "14px 16px"
---

# Design System: Workout App

## 1. Overview

**Creative North Star: "The Warm Training Cockpit"**

Workout App is a native iOS tool for a single powerlifting athlete using it between Sets on the gym floor. The visual system must feel immediate, grounded, and calm: the athlete sees the Current Session, understands the next Set, logs the exact Set Log, and returns attention to the bar.

The product now has two documented appearance directions. Dark is the original deep green and black training cockpit with mint action states. Sage Light is the softened light mode: sage-cream surfaces, grounded green action states, and less visual glare than pure white. Both modes must preserve the same hierarchy, the same compact controls, and the same native iOS behavior.

The system rejects bro-y hype, spreadsheet-shaped density, generic fitness SaaS cards, and over-gamified feedback. It should feel like a supportive training partner that respects the athlete's expertise and shows real numbers plainly.

**Key Characteristics:**
- One focused action area owns the screen.
- Dark mode uses green depth for focus, not decoration.
- Sage Light is soft and usable, never bright white or wellness beige.
- Mint and green accents are reserved for current action, selected state, and trustworthy progress.
- Liquid Glass is selective and platform-native.
- Celebration is rare and tied to Move On, not individual taps.

## 2. Colors

The palette is a restrained green system with two product appearances: original Dark and softened Sage Light. Any future palette change must preserve action clarity, high contrast, and the product mood of warm, focused, trustworthy.

### Primary
- **Dark Primary Mint**: The original Dark mode action color. Use for the Log button, current Set indicators, selected values, progress that has actually happened, and Move On Celebration marks.
- **Sage Primary Green**: The Sage Light action color. Use where Dark mode uses mint, but keep it grounded and readable against sage-cream surfaces.
- **Accent Ink and Accent Cream**: Text colors placed on saturated action fills. Use only when text sits inside mint or green action controls.

### Secondary
- **Active Set Green Glass**: The active Set surface in both appearances. It owns the athlete's attention and should be stronger than surrounding reference cards.
- **Active Stroke Green**: The active card and selected-control outline. Use it to define focus without turning every container into an outlined card.
- **Sage-Cream Surfaces**: The light-mode background and pill vocabulary. These may be cream-tinted because the product decision explicitly chose softened Sage Light, but they must remain sage-led, not tan-led.

### Tertiary
- **Skip Danger**: The hold-to-skip progress color. Use only while the athlete is actively holding to Skip or clearing logged work. It must never become a general accent.

### Neutral
- **Dark Background Top and Bottom**: The fixed full-screen gradient behind Dark mode content.
- **Sage Background Top and Bottom**: The fixed full-screen gradient behind Sage Light content.
- **Progress Track**: The rail for future Sets and inactive progress segments.
- **Last Performed Fill and Stroke**: The quiet historical reference surface above the active Set.
- **Pill Fill and Stroke**: The Weight, Reps, RPE, increment, and summary-chip surface vocabulary.
- **Session Complete**: The completed Session tile fill in the Block grid.
- **Primary Text and Muted Text**: Major values stay high contrast. Labels, source text, helper copy, and metadata use a muted text color with enough contrast for gym-floor reading.

### Named Rules

**The Mint Means Current Rule.** Mint and saturated green are for the next action, the current Set, selected state, or progress that has actually happened. Do not use them as decoration.

**The Sage-Cream Exception Rule.** Sage Light may use softened cream-sage surfaces because that is a product decision. It must not drift into amber, gold, orange, tan, or generic beige wellness styling.

**The Preview Palette Quarantine Rule.** Black, Mint Green, and Blue Light were exploration palettes. Do not expose them as product choices or use them as design-system references unless the product decision changes.

**The No Amber Regression Rule.** The older amber direction is superseded. Do not introduce antique gold, burnt orange, or flat obsidian with rare accent hits.

## 3. Typography

**Display Font:** SF Pro, system-ui, -apple-system, BlinkMacSystemFont, sans-serif
**Body Font:** SF Pro, system-ui, -apple-system, BlinkMacSystemFont, sans-serif
**Label/Mono Font:** SF Pro, system-ui, -apple-system, BlinkMacSystemFont, sans-serif

**Character:** Typography is native, familiar, and compact. Weight carries hierarchy more than font novelty: bold values for logging, semibold labels for orientation, and plain system copy for Settings and errors.

### Hierarchy
- **Display** (900, 34px, 1.08): Celebration titles and rare milestone moments only.
- **Headline** (700, 17px, 1.25): The in-card Exercise name, primary button labels, and important card values.
- **Title** (700, 20px, 1.2): Exercise section headings in the Session, Session tiles, large value pills, and compact screen-level emphasis.
- **Body** (400, 17px, 1.35): Standard Settings copy, explanatory text, and editable values.
- **Label** (600, 12px, 1.2): Pill labels, breadcrumb text, badges, progress labels, and source labels. Uppercase is allowed only for short UI labels like "Up next."

### Named Rules

**The Numbers Stay Plain Rule.** Loads, reps, RPE, Set counts, and sync state must use direct native type. Do not stylize numbers with novelty fonts, outlines, gradient text, or decorative tracking.

**The Product Scale Rule.** Use fixed native type sizes. Do not introduce fluid display typography into app UI.

## 4. Elevation

Workout App uses tonal layering, strokes, and selective Liquid Glass instead of a broad shadow system. Depth is created by a full-screen gradient, glass surfaces for high-value containers, quiet fills for controls, and 1px strokes that define tappable regions. Shadows are exceptional: the current code uses a mint glow for the Move On Celebration stamp and a stronger active Exercise focus glow, not for ordinary cards.

### Shadow Vocabulary
- **Celebration Glow**: A soft mint glow under the Move On Celebration stamp. Use only for earned celebration.
- **Active Focus Glow**: A mint glow used when an Exercise section is actively focused. Use sparingly; if every card glows, none is focused.

### Named Rules

**The Glass Has a Job Rule.** Glass belongs on active Exercise cards, onboarding, empty states, Session Controls, Settings surfaces, and system button affordances. Do not apply glass everywhere.

**The Flat At Rest Rule.** Ordinary rows, pills, and tiles are flat at rest. Use fill, stroke, and type hierarchy before adding shadow.

## 5. Components

### Buttons
- **Shape:** Gently squared native controls for logging (8px radius), capsules for icon-only Session Controls.
- **Primary:** Full-width Log button with dark text on mint in Dark mode and cream text on green in Sage Light. Use bold headline type and 14px vertical padding. The label previews the exact Set Log the athlete is about to write.
- **Hover / Focus:** Native iOS state feedback. During hold-to-skip, the button fills with Skip Danger and reveals a Skip affordance after the configured delay.
- **Secondary / Ghost / Tertiary:** Use `.buttonStyle(.glass)` for Settings, Move On, contextual menus, and compact icon actions. Use `.buttonStyle(.plain)` only when the surface itself already carries the affordance. Manual sync is a Settings row/action labeled **Sync now**, not a Session HUD icon.

### Chips
- **Style:** Value pills use an 8px radius, semibold muted labels, bold values, and a quiet fill with a 1px stroke. In Dark mode, the fill is near-black green. In Sage Light, the fill is sage-cream.
- **State:** Selected or invalid states strengthen the stroke. Invalid fields use red only on the specific bad field. Chips stay large enough for gym use and must not collapse into tiny form fields.

### Cards / Containers
- **Corner Style:** Cards use 16px radius. Tiles and pills use 8px radius. Do not exceed these values for rectangular app surfaces.
- **Background:** Active Set cards use the active green fill. Settings groups use a single glass container, not nested cards.
- **Shadow Strategy:** Use tonal layering, strokes, and Liquid Glass before shadows.
- **Border:** Use 1px strokes for cards and pills. The active or current item may use stronger mint or green.
- **Internal Padding:** Cards default to 16px. Value pills use 12px horizontal padding.

### Inputs / Fields
- **Style:** Weight and Reps edit in-place inside the value pill, preserving the same pill frame.
- **Focus:** Tapping a pill focuses only that field. Tapping outside dismisses field UI, not the active card.
**Inert-Space All-Clear Rule.** Tapping inert Session background or gaps clears transient UI without swallowing real controls. It dismisses Weight/Reps keyboard editing wherever keyboard-driven Set Log editing appears and may dismiss transient Session utility state. RPE remains chip/grid-driven, and taps on Log, Set rows, Weight/Reps pills, RPE chips, Go back, Make Current, or Settings perform their normal actions.
- **Error / Disabled:** Invalid fields use a 2px red stroke. Disabled states reduce opacity rather than changing hue families.

### Navigation
- **Style:** Standard `NavigationStack` and platform chrome. The Session header is lightweight chrome, not a floating card.
- **Active State:** Remaining Set count and current progress use the primary action color for the active appearance. The progress rail is compact, dark or sage-muted, and segmented.
- **Mobile Treatment:** This is an iPhone-first layout. The Current Session HUD may reveal a Settings-only utility pill through an intentional high-effort overpull. Do not show a visible cue for this expert gesture. Do not expose this reveal on non-current Session views, where Go back and Make Current own the top override area.

### Active Set Card

The Active Set Card is the signature component. It contains the "Up next" label, Set ordinal badge, Exercise name, Weight/Reps/RPE pills, and the Log button. It should feel like the one place to act, not one card among many.

### Session Tile

Session tiles are compact Block-grid controls. Complete, incomplete, current, and unavailable states must remain distinct in both appearances. Unavailable Sessions are visible but clearly non-interactive and labeled "Not uploaded."

### Settings Row

Settings rows use SF Symbols, semibold row labels, secondary detail text, and a chevron for navigable rows. Appearance belongs here as an app-level preference, not in the Session flow.

**Settings Own Manual Sync Rule.** Manual sync appears in Settings as **Sync now**, grouped near the Training Sheet connection. Do not expose manual sync as a Session HUD action, progress control, or pull-to-refresh affordance. The Session screen may show sync state honestly, but it should not teach the athlete to manage sync as part of normal Set logging.

### Last Performed

Last Performed is a quiet inline reference line above the active Set — plain muted text, not a card. It is static, non-tappable, and visually subordinate to the Active Set Card so it never reads as an action.

### Move On Celebration

Move On Celebration is the only large celebratory moment. It can use heavy type, ripples, haptics, and the mint stamp because it marks a real Session transition.

## 6. Do's and Don'ts

### Do:
- **Do** keep coach-authored spreadsheet structure hidden behind Sessions, Exercises, Sets, and Set Logs.
- **Do** separate Exercises in a Session with a Title-scale section heading and spacing rhythm, not a wrapping group card — the inner Active Set and Set rows are the only cards.
- **Do** make the next logging action obvious and reachable with one hand.
- **Do** show sync and pending-write state honestly. Never imply a Set Log has landed if it has not.
- **Do** use motion to explain the Settings overpull state: the Current Session HUD can subtly stretch and materialize the icon-only Settings pill after the high preview threshold, then contract if the gesture is released before commit. Reduced motion should use a simpler fade/contract treatment.
- **Do** use mint and saturated green only for current, active, selected, and completed progress states that are real.
- **Do** keep Dark mode as the original deep green and black cockpit.
- **Do** keep Sage Light soft, sage-led, and less bright than pure white.
- **Do** keep Liquid Glass selective so important workout surfaces keep their weight.
- **Do** use exact domain language from CONTEXT.md: Block, Week, Session, Exercise, Set, Set Log, Last Performed, Move On.
- **Do** preserve native iOS affordances for Settings, Sync, sheets, navigation, and text input.
- **Do** keep celebration tied to Move On and genuine Session progress.

### Don't:
- **Don't** use **Bro-y hype / aggro fitness** styling: no beast-mode copy, flames, neon-on-black aggression, or all-caps shouting.
- **Don't** make a **Spreadsheet-in-an-app** UI: no raw cell editing, dense grids, tiny tap targets, or visible row and column plumbing.
- **Don't** use **Generic fitness SaaS** patterns: no interchangeable rounded-card dashboards, stock gradients, badge spam, ring charts everywhere, or cheerful clip art.
- **Don't** over-gamify: no XP bars, points, levels, streak pressure, mascots, or confetti on normal logging taps.
- **Don't** expose Black, Mint Green, Blue Light, or other experimental palettes as product modes.
- **Don't** use amber, gold, burnt orange, tan-led neutrals, or the superseded warm-amber palette.
- **Don't** use gradient text, side-stripe borders, broad decorative glass, or repeated identical card grids.
- **Don't** add decorative motion. Motion must convey state: logging, focusing, skipping, syncing, or moving on.
- **Don't** introduce cards inside cards. Surfaces can be stacked, but each layer must have a distinct job.
- **Don't** exceed 16px radius on rectangular cards or 8px on tiles and value pills.
- **Don't** use "workout", "training day", "lift", "working set", "actual load", or "Finish Session" where the domain glossary says to use Session, Exercise, Set, Set Log, or Move On.
