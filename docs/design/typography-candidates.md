# Typography candidates for the visual redesign

Research for wayfinder ticket #410. The current system is SF Pro only, with
weight-carried hierarchy (900/700/600/400) and fixed sizes 12–34px
(`DESIGN.md` §3). This survey maps what an iOS 26 / SwiftUI app can actually
use — system families at zero bundling cost, and open-license faces worth
bundling — and shortlists six candidate pairings (display + text + numerals)
for a **warm, focused, trustworthy** training tool. Numeral quality is the
hard gate throughout: the athlete reads `27.5×10 @8 · 27.5×10 @8` on the gym
floor, mid-Session, and the Numbers Stay Plain Rule survives as an
anti-regression whatever face wins. Every pairing below keeps loads, reps,
and RPE in a verified tabular-figure face.

## System families (zero bundling cost)

Everything here ships with iOS and is reachable through SwiftUI API. Note the
license asymmetry: the *downloadable* SF/New York fonts from
[developer.apple.com/fonts](https://developer.apple.com/fonts/) are licensed
for UI mock-ups only and **cannot be embedded in an app binary** — but none of
that matters at runtime, because the OS provides these families through API.

| Family | Runtime access | What it unlocks |
|---|---|---|
| **SF Pro** (9 weights, variable optical sizes) | default system font | The current voice: neutral, native, invisible. ([SF Fonts](https://developer.apple.com/fonts/)) |
| **SF Pro widths** — Condensed, Compressed, Expanded | `fontWidth(.compressed/.condensed/.expanded)`, iOS 16+ ([fontWidth(_:)](https://developer.apple.com/documentation/swiftui/view/fontwidth(_:))) | Display contrast without changing family: Expanded reads deliberate and grounded for titles; Compressed is dense display/label material. Introduced in [WWDC22 "Meet the expanded San Francisco font family"](https://developer.apple.com/videos/play/wwdc2022/110381/); all widths share vertical proportions, so mixing widths keeps line rhythm. Width variation works only on system fonts. |
| **SF Rounded** | `fontDesign(.rounded)` / `Font.system(_:design:)` ([Font.Design](https://developer.apple.com/documentation/swiftui/font/design)) | Warmth inside the SF skeleton — rounded terminals, same metrics, full Dynamic Type. The obvious echo of the Sunbird's all-curves vocabulary. |
| **New York** (serif, 6 weights, variable optical sizes) | `fontDesign(.serif)` | Editorial, trusted, calm — a "coach's notebook" register for titles and Celebration. Adapts from reading face to display face by optical size. ([SF Fonts](https://developer.apple.com/fonts/)) |
| **SF Mono** (6 weights) | `fontDesign(.monospaced)` for the monospaced system design; the downloadable SF Mono itself targets coding environments and may not be bundled ([SF Fonts](https://developer.apple.com/fonts/)) | A data register. Usually unnecessary here: `Font.monospacedDigit()` ([docs](https://developer.apple.com/documentation/swiftui/font/monospaceddigit())) gives **tabular figures inside SF Pro itself** — aligned digits with zero change of voice. |

Takeaway: the system already offers three distinct personalities (rounded
warmth, serif calm, width-led focus) plus a first-class tabular-numeral
story, all free and all fully Dynamic-Type native.

## Bundleable open-license faces

License, weights/variable axes, and tabular-figure (`tnum`) support verified
against each face's upstream repo or official specimen. File sizes measured
from the variable TTFs hosted in
[google/fonts](https://github.com/google/fonts) (`main`, July 2026) — the
realistic bundling cost for one variable file.

| Face | License | Weights / variable | tnum | VF size | Personality note |
|---|---|---|---|---|---|
| [Inter](https://rsms.me/inter/) | OFL 1.1 | 100–900 + italics; variable with **text + display optical sizes** | **Yes**, documented | 877 KB | The UI workhorse: tall x-height, ink traps, numerals drawn for data. Quietly engineered rather than warm. |
| [Manrope](https://github.com/aaronbell/manrope) | OFL 1.1 | variable wght 200–800 | **Yes** ("Tabular Figures" + "Geometric Digits", per README) | 165 KB | Semi-condensed, rounded, minimal — soft geometry that flatters a curve-led mark. |
| [Source Sans 3](https://github.com/adobe-fonts/source-sans) | OFL 1.1 | variable wght; statics | **Yes** (tabular + lining figures) | 646 KB | Adobe's UI sans: humanist, plain-spoken, extremely legible. Warm-neutral rather than characterful. |
| [Fraunces](https://github.com/undercasetype/Fraunces) | OFL 1.1 | variable opsz 9–144, wght 100–900, **SOFT**, **WONK** | display face — numerals not for data | 360 KB | Old-style soft serif (Windsor/Cooper lineage). The SOFT axis literally rounds the forms — a rare serif that speaks the Sunbird's curve language. Display roles only. |
| [IBM Plex Sans](https://github.com/IBM/plex) | OFL 1.1 | variable wdth+wght (google/fonts build) | family-level figure features; not re-verified in repo README | 537 KB | Grotesque with engineering credibility; slightly cool/corporate for this brand. |
| [IBM Plex Mono](https://github.com/IBM/plex) | OFL 1.1 | 8 weights + italics | fixed-width by construction | 136 KB/weight | A warm, literary mono — viable dedicated numeral face. |
| [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono) | OFL 1.1 | 8 weights + italics; variable | fixed-width by construction; digits drawn for maximum disambiguation | 187 KB | Tall x-height, distinct symbols. Purpose-built glance legibility, but a visibly "developer" voice. |
| [Space Grotesk](https://github.com/floriankarsten/space-grotesk) | OFL 1.1 | variable wght | **Yes** | 137 KB | Idiosyncratic grotesque derived from Space Mono. Characterful display material, but its quirky digits fail the instant-read bar for the numeral role. |
| [Recursive](https://github.com/arrowtype/recursive) | OFL 1.1 | variable **MONO**, **CASL**, wght 300–1000, slnt, CRSV | **Yes**, plus a true MONO axis | 2.38 MB | One file spanning warm Casual display → focused Linear text → mono data. Uniquely fits "supportive partner + instrument panel," at the heaviest bundle cost here. |
| [Bricolage Grotesque](https://github.com/ateliertriay/bricolage) | OFL 1.1 | variable opsz, wdth, wght | display face; figures undocumented | 408 KB | Expressive, exaggerated ink traps, "anxious and wonky" in compressed cuts — more editorial-brand energy than calm cockpit. |
| [Figtree](https://github.com/erikdkennedy/figtree) | OFL 1.1 | variable wght 300–900 (+italic) | **not documented** — assume no | 63 KB | "Friendly, simple geometric sans." Cheap and warm, but without verified tnum it can't carry numerals alone. |
| [Instrument Sans](https://fonts.google.com/specimen/Instrument+Sans) | OFL (hosted in google/fonts `ofl/`) | variable wdth+wght | not verified | 194 KB | Neo-grotesque with width play; kept on the long list only. |

**Dropped.** *General Sans* and the other Fontshare faces ship under the
[ITF Free Font License](https://www.fontshare.com/licenses/itf-ffl), not the
OFL — bundling may be permitted but it is not an open license and would need
its own legal read; out on the license bar. *Space Grotesk* and *Bricolage*
stay in the table as display-only material but are out of the numeral role
(quirky/undocumented figures). *Zilla Slab, Spectral, Outfit, Sora* were
screened and not shortlisted: no verified tabular figures and/or a colder,
techier register than "warm training partner" (Sora and Outfit in
particular read startup-tech, and Spectral/Zilla Slab bring editorial-serif
body text this one-glance UI doesn't need).

## Mechanics

**Dynamic Type for custom fonts.** System fonts scale automatically; bundled
fonts scale only if asked:

- SwiftUI: [`Font.custom(_:size:relativeTo:)`](https://developer.apple.com/documentation/swiftui/font/custom(_:size:relativeto:))
  scales a custom font relative to a system text style (iOS 14+). The
  overload *without* `relativeTo:` scales relative to `.body` by default.
- UIKit: [`UIFontMetrics(forTextStyle:).scaledFont(for:)`](https://developer.apple.com/documentation/uikit/uifontmetrics)
  (iOS 11+) wraps a custom `UIFont` in a text style's scaling curve.
- [`@ScaledMetric`](https://developer.apple.com/documentation/swiftui/scaledmetric)
  scales non-font values (padding, pill heights) with the type size, which
  keeps Weight/Reps/RPE pills proportioned if type ever scales.
- Note the standing tension: `DESIGN.md` has a **Product Scale Rule** (fixed
  native sizes, no fluid display type). These mechanics are documented so the
  redesign can *choose* — adopting a custom face does not force Dynamic Type,
  but abandoning it should be an explicit decision, not an accident of
  `Font.custom(_:size:)`.

**Bundling.** Add font files to the target and list them under the
`UIAppFonts` ("Fonts provided by application") Info.plist key, then reference
by PostScript name — see
[Adding a custom font to your app](https://developer.apple.com/documentation/uikit/adding-a-custom-font-to-your-app).
Runtime registration (e.g. fonts outside the plist) uses
[`CTFontManagerRegisterFontsForURL`](https://developer.apple.com/documentation/coretext/ctfontmanagerregisterfontsforurl(_:_:_:)).

**Variable fonts.** iOS renders variable TTFs bundled the same way. Two
practical cautions: (1) SwiftUI's `.bold()`/`.fontWeight(...)` do not drive a
custom font's variation axes — select **named instances** by PostScript name
(e.g. `Manrope-SemiBold` inside the VF), or drop to
`UIFontDescriptor`/`CTFontDescriptor` with variation attributes for
axis-level control (relevant for Fraunces' SOFT or Recursive's CASL/MONO).
(2) OpenType features such as `tnum` are similarly not exposed as a SwiftUI
modifier for custom fonts — enable them via
[`UIFontDescriptor` feature settings](https://developer.apple.com/documentation/uikit/uifontdescriptor/attributename/featuresettings)
and bridge the result into SwiftUI. System fonts avoid both problems
(`monospacedDigit()`, `fontWidth`, `fontDesign` are all first-class).

**Cost.** One variable file per family is the model: 63 KB (Figtree) to
877 KB (Inter) to 2.38 MB (Recursive) — see the table. A two-family pairing
lands roughly 0.4–1.3 MB of the app bundle; trivial for size, non-trivial
for maintenance (license files, plist entries, feature-setting plumbing,
Dynamic Type wrappers).

## Constraints: Numbers Stay Plain survives

The rule (`DESIGN.md` §3) is the anti-regression gate for every concept:

- **Numerals must read instantly.** Loads, reps, RPE, Set counts, and sync
  state render in the pairing's designated *numeral* face — never the
  display face. Fraunces, Bricolage, and Space Grotesk digits never touch a
  load. Digits need unambiguous 3/8, 6/9, 0/O at 12–20px under gym light.
- **Tabular figures are mandatory where numbers repeat or align**: Set lines
  and Exercise History rows (`27.5×10 @8 · 27.5×10 @8` must not wobble, and
  the History Row Never Wraps Rule assumes stable digit widths for
  `minimumScaleFactor` math). System route: `monospacedDigit()`. Bundled
  route: verified `tnum` + font-descriptor plumbing (above). Faces without
  verified `tnum` (Figtree) cannot be the numeral face.
- **No stylization**: no outlines, gradient text, or decorative tracking on
  numbers, whatever face carries them — unchanged from today.
- **Default state matters**: most faces default to *proportional* figures;
  `tnum` must be explicitly enabled and component-tested in pills, Set dots
  labels, and History rows before a pairing is declared safe.

## Candidate pairings

Six candidates, ordered roughly by cost/risk. "Numerals" always means loads,
reps, RPE, counts, and sync state. On Sunbird harmony (all-curves mark, mint
on deep green): the curve-friendly options are flagged inline; none of the
shortlist fights the mark outright.

### 1. Native Warmth — SF Rounded / SF Pro / SF Pro tabular

**Display:** SF Rounded (`.fontDesign(.rounded)`) · **Text:** SF Pro ·
**Numerals:** SF Pro + `monospacedDigit()`

*The current app with its edges warmed — the Sunbird's curves let into the type.*

Zero bundle cost, zero Dynamic Type work, zero license questions; hierarchy
still carried by weight, now with a rounded display register for Exercise
names, Session titles, and Celebration. Rounded terminals are the most
literal typographic echo of the curve-led mark. Numerals stay in plain SF
with tabular figures — the strictest possible reading of Numbers Stay Plain.
Risk: rounded system type is common in consumer fitness apps; warmth without
much distinction. ([SF Fonts](https://developer.apple.com/fonts/),
[Font.Design](https://developer.apple.com/documentation/swiftui/font/design),
[monospacedDigit](https://developer.apple.com/documentation/swiftui/font/monospaceddigit()))

### 2. Quiet Editorial — New York / SF Pro / SF Pro tabular

**Display:** New York (`.fontDesign(.serif)`) · **Text:** SF Pro ·
**Numerals:** SF Pro + `monospacedDigit()`

*A coach's notebook: serif calm for the words, plain instruments for the numbers.*

New York on Session titles, Last Performed framing, and the Celebration
quote gives trustworthy, literary warmth that is the opposite of bro-y hype
— and its variable optical sizing means it holds up from 12px labels to
34px display. Data stays entirely SF, so the gym-floor read is untouched.
Zero cost. Risk: serif display can drift "wellness journal" if overused —
confine it to titles and Celebration, never pills.
([SF Fonts](https://developer.apple.com/fonts/))

### 3. Cockpit Widths — SF Pro Expanded / SF Pro / SF Pro tabular

**Display:** SF Pro Expanded (labels optionally Condensed) · **Text:** SF Pro
· **Numerals:** SF Pro + `monospacedDigit()`

*Focus as a width axis: a deliberate, grounded instrument panel, still 100% native.*

Expanded titles read slow, stable, and confident — "focused" rather than
"warm," trading the Sunbird echo for cockpit authority. Because all SF widths
share vertical proportions, mixing Expanded display over regular text keeps
line rhythm intact. Zero cost; requires only `fontWidth(_:)` (iOS 16+).
Risk: Compressed/Condensed used carelessly reads dense — exactly the
spreadsheet energy the brand rejects; widths belong on display and short
labels only. ([WWDC22 110381](https://developer.apple.com/videos/play/wwdc2022/110381/),
[fontWidth(_:)](https://developer.apple.com/documentation/swiftui/view/fontwidth(_:)))

### 4. One Warm Workhorse — Inter Display / Inter / Inter tnum

**Display:** Inter (display optical size) · **Text:** Inter ·
**Numerals:** Inter + `tnum`

*Quietly engineered clarity: one family, drawn for screens, with the best data digits in open type.*

Inter's variable file carries both a text cut (tall x-height, ink traps) and
a display cut, plus documented `tnum` — a single 877 KB file replaces the
whole stack and gives the app a subtly more contemporary, less "default
iOS" voice while staying invisible in use. The numeral story is the
strongest of any bundled option. Risk: Inter is ubiquitous in SaaS UI —
distinction comes from the green/mint world, not the type; personality gain
over SF is modest for the bundling and feature-plumbing work.
([rsms.me/inter](https://rsms.me/inter/))

### 5. Soft Geometry — Manrope everywhere

**Display:** Manrope ExtraBold · **Text:** Manrope ·
**Numerals:** Manrope + `tnum`

*Rounded, semi-condensed geometry — the Sunbird's curve vocabulary as a text system.*

Manrope's rounded joins and "Geometric Digits" give genuine warmth with a
compact, focused fit — arguably the best single-family personality match for
warm-focused-trustworthy, and at 165 KB the cheapest characterful bundle.
Documented tabular figures keep Set lines aligned. Weight range 200–800
covers the current 400/600/700 hierarchy but **not Black 900** — Display
(Celebration) would cap at 800 or borrow SF. Risk: modest weight ceiling;
lowercase-leaning quirk (Manrope's stylistic defaults) needs a specimen pass
on domain words like "RPE". ([aaronbell/manrope](https://github.com/aaronbell/manrope),
[GF metadata](https://raw.githubusercontent.com/google/fonts/main/ofl/manrope/METADATA.pb))

### 6. Warm Serif Moments — Fraunces / Source Sans 3 / Source Sans 3 tnum

**Display:** Fraunces (high SOFT, low WONK, display opsz) · **Text:** Source
Sans 3 · **Numerals:** Source Sans 3 + `tnum`

*Earned celebration in a soft-serif voice; plain humanist instruments the rest of the time.*

The maximal-personality option: Fraunces appears only where the product
already permits ceremony — Celebration titles, Block/Week headers — with its
SOFT axis dialed up so even the serif speaks in curves. Source Sans 3 is a
proven UI sans with verified tabular and lining figures carrying every
number and all body copy. Total ~1 MB across two variable files, plus the
most design-governance risk of the shortlist: two families need clear role
rules or the serif leaks into data surfaces and tips "wellness."
([Fraunces](https://github.com/undercasetype/Fraunces),
[Source Sans 3](https://github.com/adobe-fonts/source-sans))

---

**Worth watching, not shortlisted:** [Recursive](https://github.com/arrowtype/recursive)
can express pairings 4–6's whole range (Casual display → Linear text → MONO
numerals) from one OFL file with documented tabular figures — the best
conceptual fit for "one supportive voice that snaps to instrument mode" —
but at 2.38 MB and with heavy axis plumbing it's a concept-phase wildcard
rather than a default recommendation.

## Sources

- Apple — [SF & New York fonts](https://developer.apple.com/fonts/) ·
  [HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography) ·
  [WWDC22: Meet the expanded San Francisco font family](https://developer.apple.com/videos/play/wwdc2022/110381/)
- Apple API — [`Font.custom(_:size:relativeTo:)`](https://developer.apple.com/documentation/swiftui/font/custom(_:size:relativeto:)) ·
  [`UIFontMetrics`](https://developer.apple.com/documentation/uikit/uifontmetrics) ·
  [`ScaledMetric`](https://developer.apple.com/documentation/swiftui/scaledmetric) ·
  [`fontWidth(_:)`](https://developer.apple.com/documentation/swiftui/view/fontwidth(_:)) ·
  [`Font.Design`](https://developer.apple.com/documentation/swiftui/font/design) ·
  [`Font.monospacedDigit()`](https://developer.apple.com/documentation/swiftui/font/monospaceddigit()) ·
  [Adding a custom font to your app](https://developer.apple.com/documentation/uikit/adding-a-custom-font-to-your-app) ·
  [`CTFontManagerRegisterFontsForURL`](https://developer.apple.com/documentation/coretext/ctfontmanagerregisterfontsforurl(_:_:_:)) ·
  [`UIFontDescriptor` feature settings](https://developer.apple.com/documentation/uikit/uifontdescriptor/attributename/featuresettings)
- Typefaces — [Inter](https://rsms.me/inter/) ·
  [Manrope](https://github.com/aaronbell/manrope) ·
  [Source Sans 3](https://github.com/adobe-fonts/source-sans) ·
  [Fraunces](https://github.com/undercasetype/Fraunces) ·
  [IBM Plex](https://github.com/IBM/plex) ·
  [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono) ·
  [Space Grotesk](https://github.com/floriankarsten/space-grotesk) ·
  [Recursive](https://github.com/arrowtype/recursive) ·
  [Bricolage Grotesque](https://github.com/ateliertriay/bricolage) ·
  [Figtree](https://github.com/erikdkennedy/figtree) ·
  [Instrument Sans](https://fonts.google.com/specimen/Instrument+Sans) ·
  [Fontshare ITF FFL](https://www.fontshare.com/licenses/itf-ffl)
- File sizes measured from variable TTFs in [google/fonts](https://github.com/google/fonts) (`main`, July 2026).
- Repo context — `/home/user/workout-app/PRODUCT.md`, `/home/user/workout-app/DESIGN.md` (§3 Typography).
