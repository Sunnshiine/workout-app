---
target: WorkoutTracker/Views/SessionView.swift
total_score: 26
p0_count: 0
p1_count: 2
timestamp: 2026-05-31T06-43-08Z
slug: workouttracker-views-sessionview-swift
---
#### Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 2 | Session progress is visible, but successful save/sync confidence is not present in the idle main state. |
| 2 | Match System / Real World | 4 | The surface speaks in Session, Set, Last Performed, load, reps, and RPE, which matches the athlete's model. |
| 3 | User Control and Freedom | 3 | Hold-to-skip is deliberate, but hidden Session Controls and hidden RPE half-steps reduce recoverability/discoverability. |
| 4 | Consistency and Standards | 3 | Native typography and controls are solid, but nested card vocabulary blurs what is container vs. action area. |
| 5 | Error Prevention | 2 | The Log button remains visually primary when RPE is missing and does not preview the exact Set Log until all fields are valid. |
| 6 | Recognition Rather Than Recall | 2 | Prescribed RPE is badged, but half-step RPE requires knowing a long-press/drag gesture. |
| 7 | Flexibility and Efficiency | 3 | Pre-filled load/reps and compact pills support fast logging. Expert RPE entry is still slower than it needs to be. |
| 8 | Aesthetic and Minimalist Design | 3 | The screen is focused, but the parent Exercise card, Last Performed card, active card, pills, and rows create dense green-on-green stacking. |
| 9 | Error Recovery | 2 | Invalid fields can be highlighted after submit, but the button state does not tell the athlete what to fix before the failed tap. |
| 10 | Help and Documentation | 2 | The UI is mostly self-explanatory, but hidden gestures and hidden Session Controls need in-context cues. |
| **Total** | | **26/40** | **Good foundation, needs interaction clarity and tonal refinement.** |

#### Anti-Patterns Verdict

**LLM assessment**: This does not look like generic AI slop. It has a real product shape: current Set, Last Performed, prescribed values, and Set rows are grounded in the domain. The risk is different: the design is a bit too dark, intense, and container-heavy for the "warm, focused, trustworthy" product promise. It feels more like a tactical cockpit than a supportive training partner.

**Deterministic scan**: `detect.mjs --json` returned `[]` for `SessionView.swift`, `ActiveSetCard.swift`, `SmartValuePills.swift`, `SessionProgressHeader.swift`, `LastPerformedCard.swift`, `RPEGrid.swift`, `Theme.swift`, and `DESIGN.md`. No automated slop-rule findings.

**Visual overlays**: Browser overlays were not available because this is a native SwiftUI target, not an HTML/browser surface. Simulator screenshots were used as fallback visual evidence.

#### Overall Impression

The Current Session logging screen is already much closer to a real product than a prototype. The next action is visually obvious, the Last Performed reference is exactly where the athlete needs it, and the logging controls are large enough for gym use. The biggest opportunity is to make the primary action state honest: when the Set Log is incomplete, the button should not look equally ready, and the UI should teach the missing RPE and half-step interaction without forcing a failed tap.

#### What's Working

- **The primary flow is physically plausible.** Large Weight/Reps/RPE pills and a full-width Log button are usable between Sets.
- **Last Performed is well placed.** It sits above the active card, visually subordinate but close enough to inform the current decision.
- **The app avoids spreadsheet UI.** The athlete sees Exercise and Set concepts, not cells, rows, or raw Sheet structure.

#### Priority Issues

- **[P1] The Log button looks ready when the Set Log is incomplete**
  - **Why it matters**: In the screenshot, RPE is blank but the button is still saturated mint and labeled "Log". The athlete has to tap and fail before the UI explains what is missing.
  - **Fix**: Give the invalid/incomplete state its own treatment: lower emphasis, label "Choose RPE to log", and keep hold-to-skip available without making the normal tap look complete.
  - **Suggested command**: `$impeccable clarify`

- **[P1] Half-step RPE is hidden behind an undiscoverable gesture**
  - **Why it matters**: Powerlifters use 6.5, 7.5, 8.5, and 9.5 routinely. A long-press plus upward drag is efficient only after discovery; first-time use is recall-heavy.
  - **Fix**: Show half-step affordance in the RPE grid, either as compact secondary values, a split-cell treatment, or a press-state cue that appears immediately when the grid opens.
  - **Suggested command**: `$impeccable harden`

- **[P2] The screen has too many nested green containers**
  - **Why it matters**: Parent Exercise card, Last Performed, active card, value pills, RPE cells, and Set rows all use similar dark green fills and strokes. The active card still wins, but the hierarchy is more visually busy than it needs to be.
  - **Fix**: Flatten one layer. Let the active card own the green stroke, make the parent Exercise container quieter, and reduce the repeated bordered-box vocabulary around non-current Sets.
  - **Suggested command**: `$impeccable layout`

- **[P2] The tone is focused, but not yet warm**
  - **Why it matters**: PRODUCT.md asks for warm, focused, trustworthy. The shipped surface is focused and trustworthy, but the near-black canvas plus intense mint reads more tactical than supportive.
  - **Fix**: Keep the dark gym-friendly base, but soften secondary surfaces, reduce neon intensity outside the primary action, and add warmth through calmer spacing and quieter inactive states.
  - **Suggested command**: `$impeccable colorize`

- **[P3] Session Controls are too hidden for trust-critical actions**
  - **Why it matters**: Sync and Settings are pull-revealed. That keeps the workout surface clean, but sync trust is a core product principle and should not depend entirely on a hidden gesture.
  - **Fix**: Keep controls reserved, but expose sync status more persistently after writes and make the path to manual sync discoverable without cluttering the header.
  - **Suggested command**: `$impeccable polish`

#### Persona Red Flags

**Jordan (First-Timer Athlete)**: Jordan opens the Session, sees Weight and Reps prefilled, and taps "Log" before selecting RPE. The button looked ready, so the red RPE validation feels like a correction rather than guidance. Jordan also does not know that 6.5 exists behind a long press.

**Alex (Experienced Powerlifter)**: Alex wants to log 237.5x5@6.5 quickly. The current flow requires opening RPE, discovering the half-step gesture, then selecting the value. Expert data entry is close, but the hidden half-step mechanic slows the most domain-fluent user.

**Sam (Distracted Mid-Set User)**: Sam is chalky, breathing hard, and glancing down. The nested cards and repeated green borders make the active Set readable, but slightly more visually effortful than necessary. Sam needs one obvious target and one obvious missing value.

#### Minor Observations

- The contrast tokens are strong. Checked key pairs: muted text on active card is 6.78:1, primary text on active card is 12.96:1, mint text on dark ink is 13.81:1.
- The progress rail is compact and useful, but the tiny `W1 D1 >` navigation label is easy to miss.
- The Block grid looked more visually severe than the Session screen; unavailable tiles are clear but quite dim.
- The "Last Performed" source text is useful, but `Block 26 · W4 D3` is dense. It may be fine for expert users, but it is visually crowded in the small card.

#### Questions to Consider

- What should the primary button say when one required value is missing?
- Should half-step RPE be visible by default, or should the app preserve the compact six-cell grid and add a teaching cue?
- Which layer is allowed to own the green stroke: parent Exercise, active card, or pills?
- How much warmth should come from palette changes versus calmer spacing and hierarchy?
