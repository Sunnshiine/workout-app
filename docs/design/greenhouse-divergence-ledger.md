# PR #467 vs the locked Greenhouse design — the divergence ledger

Resolution asset for wayfinder ticket #473 (map #468). Every redesigned screen was rendered
from the PR #467 code (head `c929cf2`, merged with `main` on the audit branch
`claude/wayfinder-issue-473-f0f9ql`) in **both appearances** on the pinned runner/runtime
(xcode-27, iPhone 17 Pro, iOS 27.0) via the Visual suite in record mode, and compared against
the three layers of ground truth in authority order: **DESIGN.md** → the token sheet
(`docs/design/greenhouse-theme-tokens.md`) → the #470 pick manifest
(`docs/design/greenhouse-picks/`). The rendered PNGs are committed on the audit branch under
`Tests/Visual/__Snapshots__/` (the `…-day.1.png` / `…-night.1.png` pairs).

Classification: **PIXEL** = wrong value (color, radius, size, shadow) — the sighted loop can
fix it in place. **STRUCTURAL** = wrong composition, missing or extra component — likely needs
its own slice in the re-drive.

Render evidence: all 14 fixtures rendered in both appearances (28 PNGs,
[Audit Render run](https://github.com/Sunnshiine/workout-app/actions/runs/29711080039)).
The big picture the pixels add to the code audit: **the tokens are in the paint, but the
compositions are not** — the stage renders its progress as a horizontal slider-like line rather
than the living branch, the input block is the old cockpit block re-tinted, the ceremony and
connect screens drift from their picked compositions, and the Sunbird mark renders broken.
Night, to its credit, genuinely re-lights the room (washes present, green-fill Log capsule with
cream text, exactly one glow on the bud).

## 0. Why the gate can't even run on the PR as-is

- The PR deleted all committed Visual Baselines and recorded none, but the
  `WorkoutTrackerSnapshotTests` target's resource phase (in `project.pbxproj`, synced on `main`
  by #471/#483's minimal fix) still declares the baseline PNGs as build inputs. On the PR
  branch merged with `main`, `xcodebuild test` **fails at build time** ("Build input file
  cannot be found") before a single test runs. The re-drive must record baselines *and* keep
  the resource phase consistent. STRUCTURAL.

## 1. Theme.swift — tokens (mostly faithful; the divergences are in what consumes them)

Verified correct against the token sheet: all 12 paints, both living-paper wash recipes
(colors/centers verbatim), all stage/branch roles incl. night `budStroke #78F0B2` and the one
bud glow, `surface` 52%/7%, the literal `tileCurrentBorder #1F8552`, the full type role table
(Fraunces SOFT 100 / WONK 0 / wght 490, 33pt Exercise name, tnum everywhere), the named radius
family, the motion numbers (0.42 leaf, 1.0/0.10/0.35 ceremony, the wing ease), the Crisp haptic
tunings, exactly two hand-lit appearances, legacy palettes gone.

Divergences:

1. **Legacy alias layer maps live roles to wrong values** (`Theme.swift:133-157`):
   `pillFill → surface` (cream@52% day; sheet says cream@85%/6%), `pillStroke → queueStroke`
   (rgba(82,111,90,0.38)/cream@20%; sheet says 0.34/cream@16%). Live in the shipping input
   block. PIXEL.
2. **Tokens on the sheet with no implementation and no consumer**: `surfaceShadow`, `logShadow`,
   pressed fill `#0A5936`, `skipFillOverlay`, `sunGlow`, tile top-light, focus-card fill
   `rgba(248,251,238,0.96)` + cream glow rim, `cardLow`, page sunbeam, volume-control raised
   recipe, data-dot/approx-dot specs. STRUCTURAL (each surfaces as a wrong/absent effect below).
3. **The retired 8/16/28 radius scale survives and is consumed**
   (`Theme.swift:257-269`: `cardCornerRadius 16`, `lensCornerRadius 28`, `pillCornerRadius 8` …
   used by ActiveSetCard, SmartValuePills, RPEScaleScroller, WorkoutGlass, SessionQueueSheet).
   Token sheet §6: "Replaces the 8 / 16 / 28 scale"; DESIGN.md §4: no view invents a radius
   outside the family. STRUCTURAL.
4. **Hold-to-skip still commits at 0.8s** (`Theme.swift:279` → `HoldToSkipPolicy`); spec is
   **850ms**, with logged-state 900ms / skipped-state 1100ms holds unimplemented (the correct
   `Motion.holdToSkip*` constants exist, unreferenced). PIXEL + STRUCTURAL.
5. **`Theme.Haptics` has zero consumers** — no RPE detent, log, skip-dud, or stepper tick
   anywhere; no swell-and-peak Move On tuning exists (see §8). STRUCTURAL missing.
6. **`Motion.budOpen`/`budOpenDelay` (0.34/0.26) unused** — see §4 item 2. STRUCTURAL missing.
7. **Lint choke point is half-enforced**: the SwiftLint rule bans `Font.custom`/`.system(size:`
   but not `.font(.headline)` etc., which the un-rebuilt screens use throughout; `glyphFont`
   (`Theme.swift:647-649`) is an open `.system(size:)` escape hatch outside the role table.
   STRUCTURAL (enforcement gap).

## 2. Active Set Card & input block — the largest structural gap (DESIGN.md §5.2, pick input-block3-c)

The shipping card is the pre-Greenhouse composition re-skinned through the alias layer:

1. Card radius **16** + 1px stroke (`ActiveSetCard.swift:79-83`) vs the one soft container:
   radius **soft 30**, day double `surfaceShadow` / night inset cream border, padding 16/16/14.
   PIXEL on a STRUCTURALLY old card.
2. Head is an **uppercase status microlabel + carved `Set N of M` capsule badge**
   (`ActiveSetCard.swift:93-105`) vs the plain `Set 3 of 5` head (16pt/700 tnum + 14pt/500
   muted). Uppercase microlabels are the superseded sunlit-ledger register. STRUCTURAL.
3. The Exercise name **repeats inside the card** in `.headline` (`ActiveSetCard.swift:45-46`) —
   not in the locked composition. STRUCTURAL (extra component).
4. **Weight does not lead**: label "Weight" *above* a ~20pt value, 36pt steppers
   (`SmartValuePills.swift:91-135`, `WeightPillLayoutMetrics.swift:9`) vs **46pt/700 tnum
   `weightEntry` as the card's biggest number, labels below, ~54pt round steppers**. PIXEL +
   STRUCTURAL.
5. **Reps is a tap-to-type pill, not the 1–100 one-tap scroll rail** (48×44 cells, cream
   selected chip + inset action ring, prescription tick); only RPE got a rail
   (`SmartValuePills.swift:144-185`). STRUCTURAL missing.
6. RPE rail radii **8** (spec: rail 18, cells 14), chip type inline `.headline.bold` (spec
   `railChipValue` 17/700), track `pillFill@0.72` (spec railFill cream@55%)
   (`RPEScaleScroller.swift:66-98`). PIXEL.
7. **Log capsule is a radius-8 rounded rect, not a capsule**; no `logShadow` (day green drop /
   night green light); inline `.headline` instead of `logCapsule` 18/650 tnum
   (`SmartValuePills.swift:399-416`). The Set-Log preview text matches. PIXEL/STRUCTURAL.
8. **Hold-to-skip fills danger-red @0.86 with a red "Skip" badge + `forward.end.fill` icon**
   (`SmartValuePills.swift:406-441`) vs the muted `skipFillOverlay` (muted@30%); the skipped
   state lacks the transparent + muted text + 1.5px dashed empty-bed recipe. PIXEL + STRUCTURAL.
9. **No input haptics at all** (see §1 item 5). STRUCTURAL missing.

## 3. Glass — retired, but everywhere (ADR-0014, DESIGN.md §4/§8)

The colophon's glass disc should be the only glass. Instead the whole glass system survives
(`WorkoutGlass.swift`: `glassEffect`, `GlassButtonStyle`, `WorkoutGlassContainer`) with live
consumers: the stage container (`SessionStageView.swift:50`), the Move On button (`:326`),
`ActiveSetCard.swift:135`, `SmartValuePills.swift:214`, the connect flow
(`OnboardingView.swift:100-299`), and Settings (`SettingsView.swift:21,117`). STRUCTURAL —
the most widespread composition divergence after the card.

## 4. Session stage & branch (DESIGN.md §5.1, picks session-stage-a/-d)

Matches: branch geometry verbatim (2px round-cap stem, leaf/rib paths, dash 5-4, bud 2.2/s,
night glow 7px), leaf inks 0.42s on the wing ease, textless branch, dashed-leaf Skip, Set dots
retired, queue pill + plain `Up next ·` foot on the right roles.

1. **In render the branch does not read as a branch** (`seededSessionViewMatchesVisualBaseline-day`):
   with no logged Sets it draws as a dead-horizontal 2px line with a circular bud ring and
   circular future dots — a progress slider, not a rising stem with faint future strokes (pick
   session-stage-a shows angled future strokes on a climbing stem even before leaves). The
   component fixture confirms leaves exist once Sets log, but the empty-state geometry reads as
   the retired dots vocabulary. STRUCTURAL.
2. **The page composition is centered, not the pick's left-aligned editorial column**: Fraunces
   name and coach note render centered; the pick leads left with the name at the margin. No
   Cadence line renders above the name. STRUCTURAL.
3. **The old segmented Session progress header survives at the top of the stage** (`W1 D1 ›` +
   five segment bars + `5 left`) — the locked composition's header is a plain
   `Block · Week · Day` runline with `N Sets left`; segment bars are retired dots-vocabulary
   chrome. STRUCTURAL.
2. **The "next bud opens" moment does not exist** — bud state-change rides the same 0.42s
   animation (`SessionStageBranch.swift:106`); One Log, One Fill is unimplemented. STRUCTURAL.
3. **The stage is a ScrollView** (`SessionStageView.swift:49`) — the Product Scale Rule derives
   from "training surfaces never scroll" (single-page principle). STRUCTURAL.
4. Cadence renders `.textCase(.uppercase)` (`SessionStageView.swift:129-133`, also
   `ActiveSupersetSection.swift:83-87`) — the superseded editorial register. PIXEL (minor).
5. Completion stage spends a 52pt `checkmark.circle.fill` **plus** the Move On button's
   `arrow.right` (`SessionStageView.swift:201-203,322`) — two+ icons on the page whose icon
   budget the branch spent; inline `.title2`/`.headline` fonts. STRUCTURAL.
6. **Last Performed wraps and labels itself** (`LastPerformedCard.swift:25-42`,
   `ActiveSetPresentation.swift:326,336`): explicit "Last Performed" label and multi-line
   wrapping vs the label-free runline that shrinks-then-truncates, never wraps (12.5pt
   `lastPerformed` role, ≈11pt floor). STRUCTURAL + PIXEL.

## 5. Superset stage (DESIGN.md §5.4, picks superset-stage4-a/-b/-c)

Matches: partner branch routes `supersetPartnerBranch` (foliage day / foliage@0.55 night),
1.6px, no rib, never buds; queue-sheet containment (sentence-case `Superset` caption, `Unlink`,
`Pair` → `Pair with this`, no bracket glyph).

1. **Not a single forked stem**: two stacked full-width parallel stems (VStack + 4° rotation,
   `SessionStageBranch.swift:160-241`) vs one stem with the partner as a shorter drooping
   lateral. STRUCTURAL (approximate composition).
2. **The "& partner" line is `.secondary` gray** (`ActiveSupersetSection.swift:104`) vs foliage
   green by day (tone coupling) / translucent foliage at night. PIXEL.

## 6. Block grid (DESIGN.md §5.5, picks block-grid-focus4-d-2d/-3d/-6d)

Matches: focus-week expansion, wordless tiles, zero icons, no lock, dashed empty beds grouped at
the week's end, quantized quarters, mini strips at radius `mini`, night tiles re-light like
leaves.

1. Focus card fill is `surface` (cream@52%) vs the dedicated morning-light
   `rgba(248,251,238,0.96)` (`BlockOverviewView.swift:47`). PIXEL.
2. **The sunlit hour reads green, not sunlight**: glow rim = `tileCurrentBorder@0.55` stroke +
   green shadow vs the cream recipe (`cardLow` + `0 0 0 5px rgba(250,252,238,0.5), 0 6px 30px
   rgba(228,240,200,0.95)`) (`BlockOverviewView.swift:49-52`); the current tile's day glow
   falls back to green `tileCurrentBorder@0.35` vs the cream/sun `sunGlow`
   (`SessionTile.swift:83`). PIXEL.
3. **Missing light kit**: page sunbeam, tile top-light, `cardLow` shade on collapsed week cards
   (fill only at `BlockOverviewView.swift:81` — they should sit "in shade"), halo + panes.
   STRUCTURAL missing.
4. Tile bases: available/partial use `footFill` (cream@50%) vs `pillFill` (cream@85%); the
   partial bar is `leafFill@0.85` vs full-pigment `tileComplete` (`SessionTile.swift:37,57`).
   PIXEL.

## 7. Exercise History sheet (DESIGN.md §5.6, picks exercise-history6-a/-b)

Matches: skipped Sets never render (behind the `*` well), Legacy Logs best-effort chips, gutter
labels + muted Block headers, chips flow without text wrap, soft shoulders + living-paper sheet,
chart line ink@35% 1.5px, volume off by default, no action green.

1. **The carve may not read below-flat**: chip inset is a faint top *highlight*
   (`textPrimary@0.06` blurred stroke) vs the spec's dark top inner shadow
   (`inset 0 1px 2px rgba(21,33,24,0.14)`) + light bottom edge
   (`ExerciseHistorySheet.swift:233-250`). Confirmed in render: chips read as flat/soft-raised
   pills, not carved below the sheet. PIXEL.
2. Volume control raised state = `footFill` + `queueStroke` vs cream@90% + raised shadow
   (`:97`). PIXEL.
3. Block seam dashed `[3,4]` vs dotted `1 4` (`:372`); solid data dot lacks the paper core
   (`:303,384-394`). PIXEL (minor).
4. **Block headers render UPPERCASE** (`BLOCK 27`) vs the pick's quiet sentence-case muted
   `Block 27` — the superseded editorial register again. PIXEL (minor).
5. A fully-unparseable Legacy Log renders as an **empty gutter row** (`W1 D1 *` with zero
   chips); the pick's legacy rows always carry at least partial chips. Worth a call in the
   re-drive: surface the raw line in the `*` well or give the row a placeholder chip.
   STRUCTURAL (minor, edge case).

## 8. Move On ceremony (DESIGN.md §5.7, picks sunbird-moments-a/-d)

Matches: stem 1.0s → 0.10s beat → bird drops 0.35s on the wing ease, reduced-motion end state,
bird replaces the colophon, Completion-Not-Achievement (no perfect-day variant).

1. Stats-surface day shadow is `Color.black@0.08` vs the ink-based `surfaceShadow`; night
   border `Color.white@0.14` vs inset cream@10% (`MoveOnCelebrationView.swift:149-157`). PIXEL.
2. **Swell-and-peak is faked** with impact/notification generators
   (`MoveOnCelebrationView.swift:186-193`) vs one Crisp Core Haptics pattern timed to the
   ceremony (no tuning exists in `Theme.Haptics`). STRUCTURAL.
3. An uppercase, tracked action-green `MOVE ON` microlabel (`:106-112`, confirmed in render) —
   superseded register + action green as decoration (Green Means Action Rule). PIXEL (minor).
4. **The composition drifts from pick sunbird-moments-a**: the coach's quote renders as the
   giant Fraunces title (pick: the title names the completion — "Day 2, done." — with any warm
   line below), and the pick's full-width green **Continue capsule is replaced by bare "Tap
   anywhere to continue" text** — an invisible affordance on the surface DESIGN.md's Do list
   says must stay visible for a chalky thumb. STRUCTURAL.
5. Render instability: the Day/Night captures catch an early animation frame (a lone dot where
   the stem should be) — the known animated-fixture flake, already ticketed as #482; the
   re-drive should land its freeze so the ceremony baseline actually shows the grown branch +
   bird. (Not a new divergence, but it blocks pixel-verifying the ceremony at all.)

## 9. Sunbird & connect screen (DESIGN.md §5.8/§6, picks sunbird-moments-c/-e)

Matches: 28pt honesty floor clamp, negative-space bird cutout, perched songbird in the leaf
language (cream wing-hint, foliage at night, no glow), exactly two homes.

1. **The colophon wears the app's greens, not the icon's**: two-stop `#4C9E5C → #0D6B40`
   (bottom stop is `actionDay`) vs the three-stop icon glass `#4AA06C → #0E6E43 → #084E2F` with
   sheen + rim (`Sunbird.swift:131-132`). The Mark Stays Whole includes its colors. PIXEL.
2. **The mark renders broken**: in both appearances the negative-space bird cutout composites
   to **solid black** instead of showing the room through the disc
   (`sunbirdColophonMatchesVisualBaseline-day/-night`, and again on the connect screen) — the
   `destinationOut` cutout is punching to a black backing layer, not to the background. The
   Mark Stays Whole is violated by the render itself. PIXEL (high priority — it's the brand
   mark).
3. **The connect screen drifts from the flat-calm pick** (sunbird-moments-c/-e): the songbird
   floats with **no branch to perch on** (the perch is the point of The Two Perches), the
   colophon sits *above* the bird mid-screen (pick: small and quiet near the foot), and the CTA
   is a **stock white Google sign-in rectangle** instead of the green `Connect Google Sheet`
   capsule — a SaaS artifact on the calmest page. Title copy is "Connect your training sheet"
   (off-glossary: the domain word is Sheet) vs the pick's "Plant the program." STRUCTURAL.
4. The connect flow is built of **glass cards** (`OnboardingView.swift:100-299`) — see §3.
   STRUCTURAL.

## 10. Queue sheet, sync banner, Settings (DESIGN.md §5.4/§5.9)

1. **The queue sheet is not living paper** — no `presentationBackground` wash; DESIGN.md §2:
   "the queue sheet carries the washes; bare cream reads too white"
   (`SessionQueueSheet.swift`). STRUCTURAL missing.
2. Queue rows spend icons (`checkmark` per completed row, a branch per row) and the
   confirming-pair ring adds an accent glow on a retired radius-16
   (`SessionQueueSheet.swift:111-114,232-235`) — icon budget + One Glow Rule (a second glow at
   night). STRUCTURAL/PIXEL.
3. Sync banner carries an SF-symbol icon on the stage (`SyncStatusBanner.swift:20,31`) — the
   page's icon budget is already spent. PIXEL (minor).
4. **Settings is a custom glass card** with hand-built rows (`SettingsView.swift:21-117`) vs
   "native: system-owned rows, native text styles, normal Dynamic Type" (§5.9). STRUCTURAL.

## 11. What slice 8 left undone, and what the suite still can't see

- **Zero Visual Baselines recorded** by the PR (all 12 old ones deleted), and the build-input
  failure in §0 means the gate cannot go green without both re-recording and pbxproj hygiene.
- **The two flagged night surfaces were never validated on-simulator** by the PR: the Exercise
  History sheet at Night and the Block grid at Night (the `ThemeTests` programmatic half
  exists). This audit's renders now cover the sheet and a lone tile at Night — both obey the
  Room Re-lights Rule at first read — but the full Block grid remains unfixtured and unseen,
  and sign-off belongs to the owner ticket (#476).
- **Fixture coverage gaps vs the 17-pick manifest** — screens the locked design defines that
  the Visual suite cannot currently see at all:
  - Superset stage (picks superset-stage4-a/-b) — no fixture.
  - Exercise queue sheet (pick superset-stage4-c) — no fixture.
  - Block grid full focus-week layout at 2/3/6 days (three picks) — only a lone
    `SessionTile` fixture.
  - Exercise History with the volume chart ON (pick exercise-history6-b) — both fixtures
    render the ledger only.
  - Sheet-connect screen (picks sunbird-moments-c/-e) — only a 360×260 onboarding *card*
    crop, not the flat-calm full screen.
  The re-drive's "wholesale re-capture" slice should add these fixtures, or the gate will pass
  while the un-fixtured surfaces drift.
