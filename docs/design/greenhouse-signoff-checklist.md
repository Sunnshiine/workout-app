# Greenhouse re-drive — owner sign-off checklist

The pixel gates (ADR-0007 visual regression) prove the compositions *render*
correctly in both appearances. They cannot judge **feel** — motion timing,
haptic character, gesture thresholds under a chalky thumb. This checklist is
the feel pass for the Greenhouse re-drive (PRD #497), carried from the closed
sign-off ticket #476 and implemented as slice 10 (#495).

The verdict is the owner's, on a physical device, from a **WT Dev TestFlight
build**. It closes #495; anything rejected becomes a follow-up issue under
PRD #497.

Authority order for every item below: **spec #458** →
[`DESIGN.md`](../../DESIGN.md) → the token sheet
([`greenhouse-theme-tokens.md`](./greenhouse-theme-tokens.md)) → the pick
manifest ([`greenhouse-picks/`](./greenhouse-picks/)).

## Cutting the build

The build is the PRD's own draft PR (#505), archived as the **dev flavor**
(`WT Dev` on the home screen, amber Sunbird icon, live-Sheet against the dev
OAuth client — point the picker at a **cloned** training log, never the real
one). See [`docs/ci/testflight.md`](../ci/testflight.md).

1. Apply the **`testflight`** label to PR #505. The label must be applied with
   `AGENT_PAT` (a `GITHUB_TOKEN`-driven label is suppressed and never fires the
   workflow — `docs/ci/testflight.md` § Label semantics). Remove and re-apply
   for another build.
2. `.github/workflows/testflight-pr.yml` archives on the `xcode-27` runner and
   posts a receipt comment with the build number once TestFlight processing
   reports VALID.
3. Install **WT Dev** from TestFlight and work a fixture-shaped Session through
   a log, a skip, and a Move On ceremony.

### Archive / `actool` device-thinning check (carried from #478/#479)

The xcode-27 runner bump (#481, commit `e04fbec`) **removed** the old
`rm -rf WorkoutTracker/AppIcon.icon WorkoutTracker/AppIconDev.icon` workaround
from both TestFlight workflows. Xcode 26.5's `actool` could not open the Icon
Composer documents on the strict thinned/device compile — the `.icon` bundles
declare `"features": ["refractivity"]`
(`WorkoutTracker/AppIcon.icon/icon.json`,
`WorkoutTracker/AppIconDev.icon/icon.json`), a schema attribute only Xcode 27's
`actool` parses (research ticket #477, commit `e23b574` on branch
`research/xcode-27-runner`).

- [ ] The `Archive (dev flavor)` step succeeds on `xcode-27` **with the real
      `AppIcon.icon` / `AppIconDev.icon` bundles present** (no `rm -rf`
      workaround). A green archive is the device-thinned `actool` verdict; a
      `Cannot Open AppIconDev.icon` failure reopens #478/#479.
- [ ] The installed WT Dev icon renders the amber Sunbird with Liquid Glass
      refraction (not the raster `.appiconset` fallback).

## 1. The three growth moments — on the wing ease

DESIGN.md § 7 · token sheet § 7 · `Theme.wingEase`
(`cubic-bezier(0.46, -0.09, 0.83, 0.32)`) and `Theme.Motion` in
`WorkoutTracker/Theme.swift`. Custom motion is confined to these three moments;
all chrome (including the Log capsule) rides stock system springs.

- [ ] **Leaf inks on log** — `Theme.Motion.leafInk` (0.42s). Does the branch
      read as a leaf *inking in*, not a bar filling? A dashed Skip draws in the
      same language.
- [ ] **The next bud wakes** — `Theme.Motion.budOpen` (0.34s) starting
      `budOpenDelay` (0.26s) inside the leaf's tail. **One Log, One Fill:** the
      transition must read as a bud *waking*, never as a second leaf filling.
- [ ] **The Move On ceremony** — `Theme.Motion.ceremonyStem` (stem 1.0s) →
      `ceremonyBeat` (0.10s beat) → `ceremonyBird` (bird drops 0.35s), ≈1.5s at
      Brisk. Does the stem climb, hold a beat, and the bird land as one
      growth gesture?
- [ ] **Reduced motion**: with the accessibility setting on, each moment keeps
      its *end state* via crossfade (the ceremony fades in fully grown). Haptics
      are unaffected.

## 2. The Crisp haptic tunings

DESIGN.md § 7 · token sheet § 7 · `Theme.Haptics` in `WorkoutTracker/Theme.swift`.
Haptics are **Crisp, silent-chrome, semantic-only** — never on form fields or
chrome. Each tuning is `(intensity / sharpness)`.

- [ ] **RPE / rail detent tick** — `railDetentTick` (0.35 / 0.85): a clean tick
      as the thumb crosses each detent on the rail.
- [ ] **Stepper ±** — `stepperTick` (0.45 / 0.80), and **the floor hits the
      dud**: at the minimum increment the ± tap plays the dud, not the tick.
- [ ] **The firm log tap** — `logTap` (1.0 / 0.65): the firm confirmation when a
      Set logs.
- [ ] **The skip dud** — `skipDud` (0.45 / 0.15): a soft, blunt dud on skip, not
      a crisp tick.
- [ ] **The ceremony swell-and-peak** — the one Core Haptics pattern in
      `WorkoutTracker/Progress/MoveOnHapticPlayer.swift`: a continuous intensity
      swell rising through the stem's 1.0s climb, then a sharp peak transient
      landing with the bird (the log tuning, 1.0 / 0.65). One identical pattern
      timed to the ceremony choreography.
- [ ] **No haptics on form fields** — typing weight/reps into a text field is
      silent.

## 3. Hold-to-skip timing & rail/scroll feel under a chalky thumb

DESIGN.md § 7 · token sheet § 7 · `Theme.Motion` hold-to-skip constants and
`HoldToSkipPolicy` in `WorkoutTracker/Progress/ActiveSetPresentation.swift`.
The hardcoded 0.8s / 0.25s constants are retired (adopted wholesale per PRD
#497's locked decisions).

- [ ] **Reveal at 250ms** — `holdToSkipReveal` (0.25s): the skip overlay reveals
      a quarter-second into the hold.
- [ ] **Commit at 850ms** — `holdToSkipCommit` (0.85s): an idle Set commits the
      skip at 850ms; releasing earlier retreats (`holdToSkipRetreat`, 0.2s).
- [ ] **Longer holds on already-decided Sets** — a logged Set re-skips only
      after `holdToSkipLoggedCommit` (900ms); a skipped Set after
      `holdToSkipSkippedCommit` (1100ms). Does the extra resistance feel
      protective, not sluggish?
- [ ] **Rail & scroll feel** — dragging the rail and scrolling the stage with a
      dry/chalky thumb: affordances stay visible (never chrome-on-demand), tap
      targets are reachable one-handed, no accidental skips.

## 4. `danger` styling verdict

Token sheet § 9 · `Theme.Paint.danger` in `WorkoutTracker/Theme.swift`
(`rgb(255, 59, 48)` — system red, day and night). No Greenhouse prototype
styled an error state, so `danger` is **carried forward as system red pending a
dedicated DESIGN.md pass**.

- [ ] Confirm the `danger` styling from the screenshots delivered during the
      input-block slice (#488), or request a re-delivery here. Verdict: keep
      system red, or open a danger-pass follow-up under PRD #497.

## Verdict

- [ ] **Growth moments** — accept / reject (which):
- [ ] **Haptics** — accept / reject (which):
- [ ] **Hold-to-skip & rail feel** — accept / reject (which):
- [ ] **`danger` styling** — keep system red / open follow-up:
- [ ] **Archive / `actool`** — green / reopen #478/#479:

Record the verdict on PRD #497. Every rejection becomes a follow-up issue
under #497; the owner's acceptance closes slice #495.
