# Fully dynamic cell targeting — no hardcoded positions

The coach can restructure a Block tab at any time: inserting columns, reordering days, adding rows. Between Block 1 and Block 2 the sheet already grew by one column. A naive approach of caching "Set Logs go to column J" would silently write to the wrong cell after any such change.

We derive every write target dynamically at write-time by scanning the live sheet for semantic anchors:

- **Column**: scan the day's column group for the header labelled "Notes" (for Set Logs) or "Last set RPE" (for Last Set RPE). Use whichever column those headers occupy — never a hardcoded letter.
- **Row**: scan the day's column group for the exercise name, then count down to the Nth continuation row for the target set index.

Before every write (new log, edit, or delete), the app reads the current cell value and verifies it matches expectations (empty for new writes; previously-written value for edits/deletes). If verification fails — because a header was renamed, a row was inserted, or the coach edited the cell — the write is aborted and the athlete is warned. The app never guesses or overwrites unexpected content.

**Consequence**: if the coach renames a column header (e.g. "Notes" → "Athlete Log"), the app cannot locate the write target and will surface a warning until the next sync resolves the mismatch. This is the correct safe failure mode.

**Considered alternative**: cache raw cell addresses (e.g. "Block 27 · J15") at first write. Simpler to implement but silently corrupts data after any structural change — unacceptable given the coach actively edits the sheet.
