# Greenhouse → Theme.swift: the decided token sheet

Resolution asset for wayfinder ticket #422 (map #408). This records the
*decisions* the DESIGN.md rewrite (#423) encodes — implementation is out of
scope for the map. Values are extracted from the picked prototype variants
(#411, #413, #414, #418, #419, #420, #434, #435, #452, #455); conflicts
between picked variants were adjudicated in the #422 grilling and the calls
are recorded inline.

## 1. Appearances

- **Exactly two appearances ship: Day and Night** — the same room re-lit,
  never recolored (#418). Code names `.day` / `.night`.
- The standing three-way `AppearancePreference` stays: **System / Light /
  Night** in Settings. System follows iOS (system-dark → Night). "Dark"
  leaves the product vocabulary.
- **All five legacy palettes are retired** (`dark`, `black`, `mintGreen`,
  `sageLight`, `blueLight`). The `-WORKOUT_THEME` launch argument survives
  as the screenshot/test pin, with `day` and `night` as its only values.

## 2. Token architecture

- **A small paint box + flat semantic roles** (the hybrid). Views consume
  *roles only*, via the existing `@Environment(\.themePalette)` mechanism —
  the environment palette swap is how appearance switching works, and no
  view changes between architectures.
- Most role values are expressed as **paint @ opacity** (which is how the
  prototype CSS is literally written); oddballs (wash recipes, glow
  shadows, `tileCurrentBorder`) are honest literals.
- **No derivation rule maps Day → Night.** Night is a hand-lit value sheet
  (mint fails the action role at night; leaves re-light to foliage). A full
  primitive layer would lie about the system and is rejected.

### The paint box

| Paint | Value | Notes |
|---|---|---|
| `ink` | `#152118` | day text; at low opacity: carved chips, scrim, shadows |
| `inkNight` | `#EFF3E3` | night text |
| `muted` | `#526457` | day secondary text |
| `mutedNight` | `#9AAA9B` | night secondary text |
| `cream` | `#F2F7E8` | the workhorse — surfaces, pills, buds, ribs, action text (~15 roles at varying opacity) |
| `actionDay` | `#0D6B40` | day action green; also day leaf/stem/bird pigment |
| `actionNight` | `#1F8552` | night action green (mint is banned from the action role at night) |
| `foliage` | `#579168` | *the* night pigment: leaves, stems, bird, tiles re-light to this |
| `paperDay` | `#E9EEDC → #CBE1C2` | base pair under the day washes (atmosphere pick — supersedes `#E8EDDB → #C7E0BF`) |
| `paperNight` | `#232C20 → #121D14` | hue-preserved deep sage, never neutral black (#418) |

## 3. Semantic roles — Day · Night

### Paper / atmosphere (`paperWash` — #420, atmosphere2 i/k win verbatim, washes everywhere in both appearances)

Day (top layer first):

```
radial-gradient(90% 46% at 18% 4%,   rgba(255,250,224,0.85) 0%, transparent 60%)   /* warm sun wash, top-left */
radial-gradient(70% 40% at 108% 32%, rgba(163,205,154,0.55) 0%, transparent 70%)   /* sage pooling, right */
radial-gradient(80% 42% at -10% 62%, rgba(214,232,197,0.70) 0%, transparent 65%)   /* mint breath, left */
radial-gradient(110% 55% at 55% 108%, rgba(151,189,140,0.75) 0%, transparent 70%)  /* deep sage pooling, foot */
linear-gradient(180deg, #E9EEDC 0%, #CBE1C2 100%)
```

Night:

```
radial-gradient(80% 42% at 18% 4%,   rgba(255,233,170,0.14) 0%, transparent 60%)   /* warm lamp pool */
radial-gradient(70% 40% at 108% 32%, rgba(87,145,104,0.16)  0%, transparent 70%)
radial-gradient(80% 42% at -10% 62%, rgba(87,145,104,0.10)  0%, transparent 65%)
radial-gradient(110% 55% at 55% 108%, rgba(9,18,12,0.70)    0%, transparent 70%)   /* dark floor pooling */
linear-gradient(180deg, #232C20 0%, #121D14 100%)
```

The two-stop `gradientStops` token shape dies; the paper token becomes a
layered wash recipe (base pair + four radial washes), one recipe per
appearance.

### Text inks

| Role | Day | Night |
|---|---|---|
| `textPrimary` | ink | inkNight |
| `textSecondary` | muted | mutedNight |
| `homeBar` | ink @ 20% | cream @ 22% |

### Stage & branch

| Role | Day | Night |
|---|---|---|
| `stem` (2px, round cap) | actionDay | foliage |
| `leafFill` | actionDay | foliage |
| `leafRib` | cream @ 50% | cream @ 55% |
| `budFill` | cream @ 95% | cream @ 92% |
| `budStroke` | actionDay | `#78F0B2` |
| `budRib` | actionDay @ 55% | foliage @ 60% |
| `futureStroke` | actionDay @ 40% | foliage @ 45% |
| `skipStroke` (dashed 5 4) | muted @ 42% | mutedNight @ 40% |
| `budGlow` | none | `drop-shadow(0 0 7px rgba(120,240,178,0.32))` — the page's one glow |

Leaf geometry (`M0 8 C 15 2.3, 41 3.3, 60 8 C 41 21.7, 15 22.6, 0 8 Z`,
rib `M4 8.1 C 20 9.8, 40 9.6, 56 8.1`) and stroke widths (rib 1.2/s, bud
2.2/s, future/skip 1.2/s) are geometry constants, not palette. Node scale
runs are tuned per layout, not tokenized.

### Active Set Card & input block (#455 supersedes #413's pill display)

| Role | Day | Night |
|---|---|---|
| `surface` (the one soft container) | cream @ 52% | cream @ 7% |
| `surfaceShadow` | `0 1px 2px rgba(21,33,24,0.04), 0 14px 30px rgba(21,33,24,0.07)` | `inset 0 0 0 1px` cream @ 10% (border-as-light, no drop) |
| `pillFill` (stepper buttons) | cream @ 85% | cream @ 6% |
| `pillStroke` | `rgba(82,111,90,0.34)` | cream @ 16% |
| `railFill` (reps/RPE rails) | cream @ 55% | cream @ 6% |
| rail chip selected | cream fill + inset 2px `action` ring | same recipe, night values |
| prescription tick (last week) | `action`, 18×3, r2 | `action` |
| weight entry `:focus` | `action` | `action` |

Card padding: **16 / 16 / 14** (#455, latest round — supersedes #413's
18/18/16). Rail edge fade mask, 54pt steppers, chip cells 48×44, and the
composition itself are locked by #455.

### Log capsule

| Role | Day | Night |
|---|---|---|
| `action` (fill) | actionDay | actionNight |
| `actionText` | cream | cream |
| `logShadow` | `0 1px 2px rgba(13,46,28,0.22), 0 10px 22px rgba(13,60,35,0.16)` | `0 0 22px rgba(31,133,82,0.35)` (glow, no drop) |
| pressed/logged fill | `#0A5936` | — (build) |
| `skipFillOverlay` | muted @ 30% | — (build) |
| skipped state | transparent, muted text, `1.5px dashed skipStroke` | same recipe |

### Stage foot

| Role | Day | Night |
|---|---|---|
| `footFill` (queue pill) | cream @ 50% | cream @ 6% |
| `queueStroke` | `rgba(82,111,90,0.38)` | cream @ 20% |

### Block grid (#435 variant d "Light and shade"; day set — night follows the #419 rule: tiles re-light like leaves, foliage + deep-ink text)

| Role | Value (day) |
|---|---|
| `tileComplete` / text | actionDay / cream |
| `tileCurrentFill` | cream @ 95% |
| `tileCurrentBorder` | **literal `#1F8552`** + `sunGlow` — kept exactly as approved; deliberately *not* aliased to a paint (it is the night action green used as a day accent, and normalizing it to actionDay would change the validated artifact) |
| `sunGlow` | `0 0 0 4px rgba(242,247,232,0.45), 0 2px 18px rgba(220,235,190,0.9)` |
| tile top-light | `radial-gradient(90% 160% at 78% -30%, rgba(255,255,245,0.85), transparent 55%)` |
| `tileGhostStroke` (empty bed: un-uploaded day; dashed = "empty bed" incl. Skipped, amending #419) | muted @ 38%, 1.5px dashed |
| tile partial | `pillFill` + bottom bar in `tileComplete`, height quantized quarters |
| `weekCardShade` (collapsed, in shade) | `rgba(226,233,214,0.72)`, border muted @ 22%, `cardLow` |
| focus card (morning light) | `rgba(248,251,238,0.96)`, glow rim `cardLow, 0 0 0 5px rgba(250,252,238,0.5), 0 6px 30px rgba(228,240,200,0.95)` |
| `cardLow` | `0 1px 2px rgba(21,33,24,0.06), 0 3px 8px rgba(21,33,24,0.07)` |
| page sunbeam | `radial-gradient(120% 85% at 82% -8%, rgba(253,254,242,0.85), rgba(250,252,238,0.28) 46%, transparent 70%)` |

### Exercise History sheet & chips (#434; day set — night follows the #418 sheet recipe, flagged for the build, not re-prototyped)

| Role | Value (day) |
|---|---|
| `sheetFill` | `#EFF4E4`, radius 30 top shoulders, shadow `0 -8px 40px rgba(21,33,24,0.18)` |
| `chipCarvedFill` (the app's only below-flat elevation) | ink @ 5.5% + `inset 0 1px 2px rgba(21,33,24,0.14), 0 1px 0 rgba(255,255,255,0.6)` |
| volume control raised | cream @ 90% + raised shadow |
| volume control pressed | = carved chip recipe |
| chart line | ink @ 35%, 1.5px |
| Block seam | ink @ 14%, dotted `1 4` |
| data dot / approx dot | ink solid r4.5 + paper core / ink outline r4 @ 1.5 |
| `scrim` | ink @ 32% |
| `grabber` | ink @ 18% |

### Bird & colophon (#414)

| Role | Day | Night |
|---|---|---|
| `birdFill` | actionDay | foliage ("The Bird Re-lights Like a Leaf" — no glow) |
| `birdRib` (cream wing-hint) | cream @ 50% | cream @ 55% |
| colophon (whole glass mark) | 40×40pt (≥ 28pt honesty floor); glass gradient `#4AA06C → #0E6E43 → #084E2F`, sheen + rim | **unchanged at night** — the glass keeps its icon greens |

Ceremony stats surface = the shared `surface` role at radius `soft`
(sunbird-moments recipe supersedes sunlit-ledger-b's bespoke one).

## 4. Type roles

**Delivery.** Fraunces and Source Sans 3 bundle as variable TTFs
(`UIAppFonts`), selected by **named instance** PostScript names —
SwiftUI's `.bold()` does not drive VF axes. `tnum` is enabled via
`UIFontDescriptor` feature settings and bridged into SwiftUI. **No view
ever constructs a font**: every text style is one row of a single
`Theme.type` role table, and a SwiftLint custom rule bans
`Font.custom` / `.font(.system(...))` outside Theme.swift.

**Fraunces voice** (Exercise name + ceremony only): one axis setting
everywhere — `SOFT 100, WONK 0, wght 490`, `opsz` tracking the point size.
**Source Sans 3 carries everything else; every numeral role is bold +
tabular** (#411).

| Role | Face | Spec |
|---|---|---|
| `exerciseName` | Fraunces | **33pt** / 1.10 (33 wins over the direction round's 34 — every later round used 33) |
| `ceremonyTitle` | Fraunces | 38pt / 1.10, centered |
| `connectTitle` | Fraunces | 36pt |
| `sheetTitle` | Fraunces | 24pt / 1.1 (opsz 22) |
| `weightEntry` | SS3 | 46pt / 700, ls −0.015em, tnum |
| `logCapsule` | SS3 | 18pt / 650, ls +0.01em, tnum |
| `setNumber` / `setOf` | SS3 | 16pt / 700 tnum · 14pt / 500 muted |
| `railChipValue` / glyph | SS3 | 17pt / 700 · 13pt / 500 |
| `fieldLabel` | SS3 | 12pt / 600 muted |
| `coachNote` | SS3 | 15pt / 1.45 muted |
| `runline` | SS3 | 13.5pt / 600 tnum; secondary 500 muted |
| `lastPerformed` | SS3 | 12.5pt / 1.5 muted tnum, nowrap; dense floor ≈ 11pt (shrink-then-truncate, never wrap) |
| `queuePill` | SS3 | 13pt / 600 tnum |
| `historyChip` | SS3 | 12pt / 600 tnum |
| `blockTitle` | SS3 | 28pt / 700, ls −0.01em, muted |
| `cadence` | SS3 | 11pt / 600 |
| stats value / key (ceremony) | SS3 | 26pt / 700 · 12.5pt / 600 muted |

Tabular numerals on **every** numeric element (Numbers Stay Plain
survives). The sunlit-ledger register (opsz 72 display, uppercase
microlabels, italic coach note, hairlines) is superseded — do not carry.

## 5. Dynamic Type stance

**The Product Scale Rule survives: fixed sizes** — now derived from the
newly explicit **single-page principle** (the training surfaces never
scroll; every locked composition was validated at fixed proportions and
fluid type would un-validate all of them).

Made **ETC** (easier to change), not merely frozen:

1. The `Theme.type` role table is the single choke point; adopting
   Dynamic Type later = each row gains `relativeTo:` — a one-file diff,
   zero view edits (visual re-validation is the unavoidable residue).
2. The SwiftLint rule keeps the choke point from eroding — and
   neutralizes the #410 trap that `Font.custom(_:size:)` silently
   *scales* by default.
3. Type-coupled geometry (54pt steppers, rail heights, pill min-heights)
   stays in Theme constants, ready to graduate to `@ScaledMetric` if the
   stance ever reverses.
4. **System-owned surfaces (Settings, alerts, share sheet) keep native
   text styles and scale normally** — the accessibility posture is not
   zero.

## 6. Radius family

Named tokens, concentric-nesting logic (inner radius ≈ outer − inset); no
view invents a radius outside the family. Approved pixel values are kept —
not rounded to a prettier scale.

| Token | Value | Used by |
|---|---|---|
| `capsule` | ∞ (999) | all controls: pills, steppers, queue pill, Log capsule, ledger chips, volume control |
| `soft` | 30 | the one soft container: Active Set Card, ceremony stats, sheet shoulders |
| `focusCard` | 24 | the Block grid's focus card |
| `card` | 20 | collapsed week cards |
| `rail` | 18 | reps/RPE rails |
| `tile` | 15 | day tiles |
| `cell` | 14 | rail chips |
| `mini` | 6 | week mini-chips |
| `hairline` | 2–3 | grabber, home bar, prescription tick |

Replaces the 8 / 16 / 28 scale.

## 7. Motion & haptics (transcribed — decided in #421/#452/#455, no new decisions)

- **Wing ease** `cubic-bezier(0.46, -0.09, 0.83, 0.32)` — the signature
  timing, confined to the three growth moments; all chrome (including the
  Log capsule) on stock system springs.
- Leaf inks **0.42s**; next bud opens inside the tail (starts 0.26s in,
  runs 0.34s) — **One Log, One Fill**: the bud wakes, it never reads as a
  second leaf filling.
- Ceremony at Brisk: stem 1.0s, 0.10s beat, bird drops 0.35s (≈1.5s).
- Haptics **Crisp**, silent-chrome, semantic-only: RPE detent 0.35/0.85 ·
  log 1.0/0.65 · skip dud 0.45/0.15 · stepper ± 0.45/0.80 (floor hits the
  dud) · one swell-and-peak Move On timed to the ceremony · none on form
  fields.
- Hold-to-skip: reveal 250ms, commit **850ms**, retreat 0.2s ease-out;
  logged-state hold 900ms, skipped-state hold 1100ms (supersedes the
  current 0.8s/0.25s constants).
- Reduced motion: end states via crossfade (ceremony fades in fully
  grown); haptics unaffected.

## 8. Conflict adjudications (recorded)

1. **Day paper**: atmosphere2-i wins verbatim, base stops included — #420
   was the dedicated authority on paper; the input-block lab's wash was
   stage dressing, never grilled as a paper decision.
2. **Night paper**: washed (atmosphere2-k) everywhere; plain two-stop
   night screens simply predate #420.
3. **Card padding**: 16/16/14 (#455, later round on the same question).
4. **Exercise name**: 33pt.
5. **`tileCurrentBorder`**: stays the approved literal `#1F8552`, named
   honestly as its own token rather than aliased to a paint.
6. **Ceremony stats surface**: sunbird-moments recipe (shared `surface`,
   radius `soft`) supersedes sunlit-ledger-b.

## 9. Carried forward / build flags (no new decisions)

- `danger` stays the current system red pending the DESIGN.md rewrite; no
  Greenhouse prototype styled an error state.
- Exercise History sheet night values follow the #418 sheet recipe (#434
  flagged: not re-prototyped — validate during the build).
- Block grid night values follow #419 (foliage tiles, deep-ink text).
- The SwiftLint font rule and the palette-struct reshaping are
  implementation work for the /to-spec build, out of scope for this map.
