# Design System: the screens beyond the stage (DESIGN.md §5.5–§5.9)

Part of [DESIGN.md](../../DESIGN.md), which holds the overview, color, type, surfaces, and the
rules for every screen that these specs serve. The Sunbird is in [sunbird.md](sunbird.md) and
motion in [motion-and-haptics.md](motion-and-haptics.md). A § number names a section of
DESIGN.md or of one of its component files, which keep its numbering.

### 5.5 Block grid — the focus week

**The growth vocabulary does not extend to the Block grid.** Tiles are
plain, wordless, wider-than-tall; state is fill + stroke alone: inked
complete (green fill, cream text), cream-bud current (cream @ 95% with the
`tileCurrentBorder` rim, leaf 600, + sun glow), quiet available, ghost unavailable.
Zero icons on the tiles — the lock icon is dead — and Fraunces stays off the
page. The grid carries two control glyphs, not tile decoration: the
`gearshape` Settings button at its foot, and the `tablecells` View Sheet
button in the navigation bar. View Sheet opens the Block's tab one Week at a
time, each Day's section as the spreadsheet shows it with its empty rows and
columns dropped, raw cells under their column letters, a debugging read-out
and the one place the app shows Sheet structure.

- **Focus-week layout:** only the week holding the Current Session expands.
  Every collapsed week is an elevated tappable card in shade, carrying a
  summary and a mini day-strip; the focus card alone stands in morning
  light with a glowing rim — hierarchy by **light and shade at one
  elevation**.
- **Partial day:** ink rising from the tile's foot in quantized quarters.
- **Empty bed:** an un-uploaded day is a dashed empty slot **grouped at the
  week's end**. Dashed means "empty bed" everywhere: Skipped Set and
  un-uploaded day alike.
- The **sunlit hour** (halo + panes + wash on the focus card) is the page's
  only delight — no branches, no bird.
- Night: complete tiles re-light like leaves (the Night leaf, leaf 300).
  The current tile is lamp-lit cream @ 14% under the bud's rim, as Day's
  is sunlit cream.

### 5.6 Exercise History sheet — the chip ledger

A sheet (the system's own corners, living-paper fill) opened only from Last
Performed. Every Set is a small **carved chip** — `27.5×10 @8`, inset into
the sheet — flowing off a `W1 D1` gutter label under quiet muted Block
headers, newest first. Chips may flow to a second line; text never wraps.

- **Skipped Sets never render.** All annotations — fallback spelling, Legacy
  Log rawness, skips — hide behind a `*` on the W/D label that expands into
  a small carved well. Legacy Logs render best-effort parsed into chips.
- A **Volume control** (chip-vocabulary pill carrying the
  `chart.xyaxis.line` glyph, no word; raised when off, pressed-in when active,
  off by default, selected to VoiceOver when active) toggles a **total-volume
  chart**: weight × reps per session, ink line, hollow `≈` dots where Legacy
  Logs make totals approximate, a dotted Block seam.
- Night follows the night sheet recipe (flagged for build validation — not
  re-prototyped).

**The History Is Reference Rule** (carried forward, restated). No action
green in the sheet beyond the control vocabulary; history is quiet reading
material — no trend arrows, badges, or dashboard chrome. The volume chart is
the one chart, athlete-summoned and off by default.

### 5.7 Move On ceremony

The ceremony is the **only performed growth** in the app and the only large
celebratory moment, marking the athlete's explicit choice to Move On. On
living paper: the stem grows (1.0s), a 0.10s beat, then the **perched
songbird drops to the branch tip** (0.35s) — ≈1.5s total, at Brisk. The
Fraunces ceremony title speaks; the stats render on the shared soft surface
(`statsValue` 28pt / 700, `statsKey` muted). With the bird present, the colophon is
absent and the composition re-centers.

**Completion, Not Achievement Rule.** The ceremony marks completion of the
athlete's choice, not the quality of the day — it must not curdle on an
ordinary day with Skipped Sets. The bird is brand, not badge. There is no
richer variant for a perfect Session (that rule is dead), no elapsed-time
UI, no confetti, XP, badges, or route previews. The ceremony closes on a
full-width green capsule carrying the `sunrise` glyph, labeled Continue to
VoiceOver.

**The No Fixed Day Count Copy Rule** (carried forward). No "only three days
left" or "halfway there" unless derived from the Week's actual Session count.

### 5.8 Sheet-connect screen

The second bird perch: a **flat calm** composition — the perched songbird
centered, the 40pt glass colophon above the ≥28pt floor, quiet copy.
Onboarding carries no monumental brand moment (prototyped and declined) and
sync carries no brand duty.

### 5.9 Settings

Settings stay native: system-owned rows, native text styles, normal Dynamic
Type. Action rows lead with a glyph in place of their label (`tablecells` for
Training Sheet, `arrow.triangle.2.circlepath` for Sync now) and keep their
value text; Sign Out is its glyph alone and Done is a checkmark. Action rows
keep system blue and Sign Out keeps system red; no contrast fix retints them
(operator ruling 2026-10-11). Appearance (System / Light /
Night) lives here.

**The Destructive Confirmation Card.** Signing out or switching sheets while
Set Logs are pending asks first, on a card the app draws in place of a system
alert, because an alert action drops its glyph on iOS 26. The card dims the
surface under it and carries the question, the line "Pending logs for the
current sheet will be discarded.", a text Cancel capsule, and a capsule
holding the red action glyph (`rectangle.portrait.and.arrow.right` to sign
out, `arrow.left.arrow.right` to switch). It behaves as a system alert does:
the sheet under it cannot be swiped away until the athlete answers,
VoiceOver moves to its title when it appears, and the escape gesture cancels
it.

**Settings Own Manual Sync Rule** (carried forward). Manual sync is a
Settings row, its glyph labeled **Sync now** to VoiceOver, never a Session
control or pull-to-refresh affordance. The Session may show sync state honestly, but
never teaches the athlete to manage sync mid-Session.
