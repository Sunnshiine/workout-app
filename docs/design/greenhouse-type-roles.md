# Greenhouse type roles

The type half of [the token sheet](greenhouse-theme-tokens.md). Section numbers continue from it.

## 4. Type roles

Revised 2026-10-31 by the typography pass of the Emil redesign. Operator ruling that day: "Where
Emil's recommendation conflicts with an existing rule in DESIGN.md, PRODUCT.md, or a past operator
decision, Emil wins."

**Delivery.** Fraunces and Source Sans 3 bundle as variable TTFs
(`UIAppFonts`), their axes driven through `UIFontDescriptor` variation
attributes, because SwiftUI's `.bold()` does not drive VF axes. Source
Sans 3 requests `tnum` on every role. **No view ever constructs a font**:
every text style is one row of the role table in
`Sources/WorkoutTracker/ThemeType.swift`, and a view sets it with
`themeFont(_:)`, which applies the face, size, tracking and leading
together and scales them with Dynamic Type (§5). A SwiftLint custom rule
bans `Font.custom` / `.font(.system(...))` outside that file, and another
bans a hand-set `.lineSpacing` or `.italic()` in a view.

**Fraunces voice** (Exercise name + ceremony only): one axis setting
everywhere — `SOFT 100, WONK 0, wght 490`, `opsz` tracking the rendered
point size. It takes no tracking, because `opsz` respaces it per size.
**Source Sans 3 carries everything else**, on the scale 12 · 13 · 15 · 17
· 28 · 46 · 96 and the weights 400 · 600 · 700.

**Tracking follows size** (Source Sans 3 only): +0.01em under 13pt, 0 from
13 to 27pt, −0.01em from 28pt, −0.015em from 46pt, read at the size the text
renders after Dynamic Type. It is computed, so no row sets it.

**Leading** is a multiple of the point size and set only on roles that wrap.

| Role | Face | Spec |
|---|---|---|
| `exerciseName` | Fraunces | 33pt / 1.1; two lines, shrinks to 80%, then truncates |
| `ceremonyTitle` | Fraunces | 36pt / 1.1, centered |
| `connectTitle` | Fraunces | 36pt / 1.1 |
| `sheetTitle` | Fraunces | 24pt / 1.1 (opsz 22) |
| `supersetPartner` | Fraunces | 20pt, one line |
| `queueName` | Fraunces | 20pt / 1.1; two lines; the queue sheet's names (operator, 2026-11-06: "Let's do Lens!") |
| `queueNameOnStage` | Fraunces | 24pt / 1.1; two lines; the queue sheet's name on stage (same ruling) |
| `heading` | SS3 | 17pt / 600; utility section heads and picker rows, where Fraunces may not go |
| `weightEntry` | SS3 | 46pt / 700 |
| `countdownNumeral` | SS3 | 96pt / 700; an Effort Countdown's seconds, read at arm's length (#1157) |
| `logCapsule` | SS3 | 17pt / 600 |
| `setNumber` / `setOf` | SS3 | 17pt / 700 · 15pt / 400 muted |
| `railChipValue` / glyph | SS3 | 17pt / 700 · 13pt / 400 |
| `fieldLabel` | SS3 | 13pt / 600 muted |
| `coachNote` | SS3 | 15pt / 400 / 1.5 muted |
| `runline` | SS3 | 13pt / 600; secondary 400 muted |
| `lastPerformed` | SS3 | 13pt / 400 muted, nowrap; shrinks to the 12pt dense floor, then truncates |
| `queuePill` | SS3 | 15pt / 600 |
| `historyChip` | SS3 | 12pt / 600 |
| `blockTitle` | SS3 | 28pt / 700, muted |
| `cadence` | SS3 | 13pt / 600 |
| stats value / key (ceremony) | SS3 | 28pt / 700 · 13pt / 600 muted |
| `sheetCell` | SS3 | 12pt / 400; the Sheet tab's Day sections, single line, truncating |

The operator, 2026-11-06: "Make the UI / UX emil approved. It should look way better and easier on the eyes." `fieldLabel`,
`cadence`, and the stats key rose from 12pt to 13pt and `queuePill` from 13pt to 15pt, so nothing an
athlete reads mid-Session sits at the floor.

The pass collapsed the half-point sizes (12.5, 13.5), the one-offs (11,
14, 16, 18, 26, 38), and the weights 500 and 650 onto the scale, and
raised the dense floor from ≈11pt to 12pt. The sunlit-ledger register
(opsz 72 display, uppercase microlabels, italic coach note, hairlines) is
superseded — do not carry.

## 5. Dynamic Type stance

Superseded on 2026-10-31: text now scales with Dynamic Type (DESIGN.md §3, The Product Scale Rule).

1. Each role scales on the Dynamic Type curve of the system text style
   `Theme.TypeScale` assigns it (`Theme.scaledSize(_:at:)`), so the 33pt
   Exercise name rides the large-title curve and grows less than the 15pt
   coach note on the subheadline curve. At the default `.large` size every
   role keeps its table value.
2. `Theme.TypeScale.largestSize` (`.xxxLarge`) caps every role on every
   screen. `SessionStageLayoutTests.atTheTypeCeilingBothStagesKeepEveryLineOnOnePage`
   proves the stage still fits at the cap.
3. Fraunces' `opsz` follows the rendered size, and tracking and leading
   scale with it.
4. Type-coupled geometry (54pt steppers, rail heights, pill min-heights)
   stays fixed in Theme constants. Up to the cap the scaled text fits
   inside it.
5. System-owned surfaces (Settings, alerts, share sheet) keep native text
   styles and scale fully.
