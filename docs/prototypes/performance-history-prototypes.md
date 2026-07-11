# Performance History Sheet Prototypes — Notes

> **Status: OPEN — awaiting the athlete's pick.** Three variants live in
> [`performance-history-sheet.html`](performance-history-sheet.html); the
> verdict lands on
> [Prototype the Performance History view #341](https://github.com/Sunnshiine/workout-app/issues/341).

## The question being answered

Given the scope decisions from
[Scope Performance History #340](https://github.com/Sunnshiine/workout-app/issues/340)
— last ~5 performances, movement-level matching across Cadence variants,
opened by tapping the Last Performed line mid-Session, primary reading
"pick my starting weight" — what presentation makes that history read at a
glance ("avoid wall of text, elegant, snappy") inside the Warm Training
Cockpit?

## How to view

Open `docs/prototypes/performance-history-sheet.html` in a browser. Flip
variants with the floating bar, `←`/`→` keys, or `#a`/`#b`/`#c` in the URL.
The mock renders the Dark cockpit: the Session stage dimmed behind a
`.medium`-detent history sheet.

## The variants

All three share: the sheet opens from the Last Performed line; title is the
cadence-stripped movement name ("Incline DB Press"); most-recent-first; each
entry shows its own Cadence prefix so movement-level over-matching stays
legible; fully Skipped occurrences omitted; partial performances keep their
`skip` markers inline; Legacy Logs display raw entered text with a quiet
`LEGACY` tag; no mint — history is reference, so it stays in the quiet
Last Performed surface vocabulary.

They disagree about **information hierarchy** — what the eye lands on first:

| Variant | Structure | Glanceability bet |
| --- | --- | --- |
| `a` **Ledger** | Five flat rows, each a context line (Cadence · Block · Week · Day · recency) over the full comma-separated Set Log line. | The athlete already reads Set Log vocabulary fluently — five plain lines in the exact format they log in is the fastest possible read, no interaction needed. |
| `b` **Top Set First** | Each row leads with the performance's top set, large ("65×8 @9"); the full Set Log line is disclosure — tap to expand. Most recent row starts expanded. | For picking a starting weight, the top set is the signal and the rest is noise; emphasis + detail-on-demand beats uniform density. Weakness on display: Legacy Logs have no parseable top set, so that row degrades to raw text. |
| `c` **Block Digest** | Rows grouped under Block section headers ("Block 27", "Block 26"), each row a Week·Day label beside its Set Log line. | Trajectory is read through program structure — grouping by Block shows *where in the training arc* each number sits, which is how the athlete already thinks about progress. |

## Fixture story rendered

An accessory movement (per #340, accessories are where history matters most)
with every display state the scope decision names:

- **B27 · W2 · D2** — `0:2:0` — `60x10@7, 65x9@8, 65x8@9` (structured; this is also the Last Performed line on the stage behind)
- **B27 · W1 · D2** — `0:2:0` — `60x10@7, 60x10@8, skip` (partial with inline skip marker)
- **B26 · W4 · D2** — `2-3:2:0` — `55x10@8, 55x9@8.5, 55x8@9` (different Cadence variant, same movement history)
- **B26 · W3 · D2** — Legacy Log, raw text: `55x10, 55x9@9, 50`
- **B26 · W2 · D2** — `2-3:2:0` — `50x12@7, 55x10@8, 55x10@9`

The five entries also encode a visible upward trend (50s → 65s), so the
"am I progressing" secondary reading can be judged in each layout.

## Decisions & deviations log

- **Static HTML, not SwiftUI.** The prior Session View Lab ran variants in the
  app; this session runs in a cloud container with no Xcode/simulator, so the
  cheapest reactive artifact is a token-faithful HTML mock (colors, type
  scale, radii, and surface vocabulary copied from `DESIGN.md` front matter).
  The winner gets built properly in SwiftUI during implementation — this file
  is throwaway.
- **Dark cockpit only.** One appearance is enough to judge structure; Sage
  Light follows the same hierarchy by design-system rule.
- **Sheet, `.medium` detent.** Matches the queue sheet's established pattern
  for on-demand orientation (The Stage Shows One Thing Rule: history must not
  live ambiently on the stage).
- **No mint anywhere in the sheet.** Mint Means Current — history is
  reference. Skip markers render muted-italic, not Skip Danger red (that color
  is reserved for the active hold-to-skip gesture).
- **Recency labels ("4 days ago") are a proposal**, not decided scope — they
  appear in variants A and B so the athlete can react to whether recency
  matters next to Block·Week·Day coordinates.

## Verdict

_Pending the athlete's reaction — recorded on
[#341](https://github.com/Sunnshiine/workout-app/issues/341) when picked._
