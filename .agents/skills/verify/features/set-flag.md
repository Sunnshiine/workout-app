# Set flag

<!-- doc-symbols: not-in-tree perStep -->

A Set Flag tells the coach something about one logged or skipped Set, as a Cell Note on that Set's cell in the Sheet. The athlete raises it from the flag in the head of a Set they came back to, logged or skipped, or from a held Set's More menu. Nothing ever prompts for one. It waits in the pending-write queue as a Set Log does, and the card says where it stands until the note lands.

## Sub-features

- `flag-review` raises a flag from the flag in a reopened Set's head, logged or skipped.
- `flag-more` raises a flag from a held Set's More menu.
- `flag-sheet` is the sheet: the Exercise and the Set, four kinds, optional words (`Other` needs them, and words typed before a kind choose it), and the capsule that names the Set.
- `flag-standing` is where a flag stands, on the card, in the sheet, and on the branch: `Unsynced`, `In the Sheet`, or `Flag not written`.
- `flag-note` reads the Cell Note in the workbook through View Sheet or `workout sheet --cell`, with the cell's value unchanged.

## How to get to it (user POV)

- Reopen a logged or skipped Set from its leaf, then tap the flag in the card's head.
- While a spoken Set is held on the card, open More, then `Flag this Set`.
- Read the note from the Block grid: `View Sheet`, then tap the cell.

## Driving it with verify.sh

Preconditions:

- Each bullet follows the one before it from `VERIFY_RUN=set-flag verify.sh launch session -UITEST_OFFLINE -UITEST_DICTATION "235 for 5 at 7"`, the fixture Sheet read as Offline.

- **Flag a reviewed Set.** Run `verify.sh tap --id log-active-set-button`, then `verify.sh tap --label "Set 1, 237.5x5@6"`. `verify.sh find set-flag-control` reads `Flag Set 1`. Run `verify.sh tap --id set-flag-control`. `verify.sh find set-flag-set-line` reads `Set 1 · 237.5×5 @6`, and `verify.sh find set-flag-raise-button` shows the capsule disabled until a kind is chosen.
- **Choose a kind.** Run `verify.sh tap --id set-flag-kind-pain`. The chip reports selected, and the capsule `Flag Set 1` enables. Run `verify.sh tap --id set-flag-words`, `verify.sh type "left hip pinch"`, then `verify.sh tap --id set-flag-raise-button`. The sheet closes.
- **See it wait.** The card's head reads `Unsynced` beside a filled flag, where the outline is the control that offers one, and the header reads `Sync status: 2 unsynced`. The branch's leaf carries the flag's mark.
- **Flush.** Run `verify.sh online`, then make the next write, which runs the queue: tap Set 2's leaf, then `verify.sh tap --id log-active-set-button`. Set 1's leaf now reads `Flag: In the Sheet`, and the header's sync status is gone.
- **Read the note.** Run `verify.sh tap --id session-location-button`, `verify.sh tap --id block-overview-view-sheet`, then `verify.sh tap --id sheet-cell-K18`. This fixture's K15 holds coach prose, so Set 1's Set Log and its note take row 18. `verify.sh find sheet-tab-cell-detail` reads `237.5x5@6`, unchanged, and `verify.sh find sheet-tab-cell-note` reads `Note: Set 1 · Pain: left hip pinch`.
- **Flag a held Set.** Run `verify.sh stop`, launch as above, then `verify.sh hold say-set-button`. While `Saved` shows, run `verify.sh axe tap -x 360 -y 505 --post-delay 1` on More, then `verify.sh tap --label "Flag this Set"`. The sheet opens and the card stays on the held Set under it. Raise a flag or swipe the sheet down, and the card moves on at once, as closing the More menu without a Clear does. Set 1's leaf carries the flag's mark.
- **Flag a skipped Set.** Hold the Log capsule until the Set skips, reopen its leaf, then run `verify.sh tap --id set-flag-control`. `verify.sh find set-flag-set-line` reads `Set 1 · Skipped`.
- **Stored value.** Prove the cell headlessly with `workout flag w1d1.e0.s0 pain "left hip"`, `workout flush`, and `workout sheet --cell K15`, as `cli-headless.md` does. That scenario's K15 is empty, so the flag takes it. `cellNote` holds the sentence, and `value` holds what it held before.

## Gotchas

- `verify.sh tap` checks the element before it taps, and on a loaded host that outlasts the four-second hold. The tap then lands on the next Set's mic, which logs that Set. Reach More with the raw `axe tap` above.
- On a very loaded host `verify.sh tap` can report success while the event never arrives. Add `--pre-delay 0.5 --post-delay 1`.
- Under load a held Set's drive still misses its four seconds. Run the mic hold, the More tap, and `Flag this Set` as one `verify.sh axe batch --ax-cache perStep --file <steps>`, with `touch -x 360 -y 505 --down --up --delay 1.2` for the hold.
- A Set with raised flags opens the sheet tall. To close it, drag from the grabber with `verify.sh axe swipe --start-x 200 --start-y 72 --end-x 200 --end-y 600 --duration 1.0`, then tap above the sheet. A faster swipe gets dropped under load.
- A raw `verify.sh axe tap` on a chip needs `--post-delay 1`. Without it none of 12 landed, with it all 6 did, and so did all 6 of an 80 ms `axe touch -x 112 -y 526 --down --up --delay 0.08`, so the lost tap is the driver's and not the app's. `verify.sh burst NAME axe tap -x 112 -y 526 --post-delay 1` landed 3 of 4, so check the capsule after a burst.
- `verify.sh online` brings only a `-UITEST_OFFLINE` launch back. A flag raised online flushes as it closes, so you see `In the Sheet` without `Unsynced`.
- `Flag not written` appears only when the Exercise has no Visible Writable Row. `swift test --filter SetFlagFlushTests` and the CLI exit 4 path prove it. The app's fixtures have no scenario that drives it.
- The fixture workbook is local, so a green flush proves the queue and the cells, not Google. The `spreadsheets:batchUpdate` request is pinned by `GoogleSheetsCellNoteTests` and was never sent to a real Sheet from here.
- A Superset's lateral arm draws no flag mark. The card still shows the standing.
