# Fully dynamic cell targeting — no hardcoded positions

The coach can restructure a Block tab at any time: inserting columns, reordering days, adding rows. Between Block 1 and Block 2 the sheet already grew by one column. A naive approach of caching "Set Logs go to column J" would silently write to the wrong cell after any such change.

We derive every write target dynamically at write-time by scanning the live sheet for semantic anchors and row visibility metadata:

- **Column**: scan the day's column group for the header labelled "Notes" (for Set Logs) or "Last set RPE" (for Last Set RPE). Use whichever column those headers occupy — never a hardcoded letter.
- **Row**: scan the day's column group for the Exercise name, then resolve the Exercise's Visible Writable Row inside that same Session. Set Logs for the Exercise are written as one comma-separated list in the Notes column. If the Exercise header Notes cell is available, the Exercise row is the target. If the header Notes cell contains a Coach Note, scan downward from the Exercise row to the next Visible Writable Row, stopping before the next Session boundary. Rows hidden by the user or by a filter are not visible and must never be selected. If no Visible Writable Row exists, or if the selected row's Notes cell contains an unexpected value, the write conflicts instead of guessing or crossing into another Session.

**Duplicate role headers.** A coach sheet can repeat a role header across adjacent columns where only one carries data — e.g. a stray empty second "Sets" column in some Day 2 sections. When a label matches more than one column in a day's group, the resolver prefers the column holding values in that day's body rows and falls back to the leftmost match, so a blank duplicate cannot shadow the real column (the cause of the W3/W4 Day 2 single-set bug).

Before every write (new log, edit, or delete), the app reads the current cell value and verifies it matches expectations (empty for new writes; previously-written value for edits/deletes). If verification fails — because a header was renamed, a row was inserted, or the coach edited the cell — the write is aborted and the athlete is warned. The app never guesses or overwrites unexpected content.

For a pending-write flush batch, the app may reuse one freshly fetched sheet snapshot per Block tab and apply each successful write to that in-memory snapshot before resolving the next queued write. This reduces redundant fetches while preserving dynamic targeting: targets are still resolved from semantic anchors and visibility facts at flush time, and raw cell addresses are never persisted across syncs or app launches.

**Consequence**: if the coach renames a column header (e.g. "Notes" → "Athlete Log"), the app cannot locate the write target and will surface a warning until the next sync resolves the mismatch. This is the correct safe failure mode.

**Considered alternative**: cache raw cell addresses (e.g. "Block 27 · J15") at first write. Simpler to implement but silently corrupts data after any structural change — unacceptable given the coach actively edits the sheet.
