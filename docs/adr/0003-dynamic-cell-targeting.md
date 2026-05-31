# Fully dynamic cell targeting — no hardcoded positions

The coach can restructure a Block tab at any time: inserting columns, reordering days, adding rows. Between Block 1 and Block 2 the sheet already grew by one column. A naive approach of caching "Set Logs go to column J" would silently write to the wrong cell after any such change.

We derive every write target dynamically at write-time by scanning the live sheet for semantic anchors:

- **Column**: scan the day's column group for the header labelled `Last set RPE`. Last Set RPE writes use that column. Set Log writes use the column immediately to its right when that adjacent column remains inside the Day group. The header labelled `Notes` is still scanned separately as the Coach Note and Legacy Log source. Never hardcode a column letter.
- **Row**: scan the day's column group for the exercise name, then resolve the target Set row relative to that anchor. In compact layouts where the Exercise header row is also Set 1, an empty Set Log header cell is writable for Set 1, and Set 2 starts on the first continuation row or aggregates into the header according to the existing compact behavior. If the Set Log header cell is non-empty and does not match the expected app-written value, it is treated as protected content and Set Logs fall back to safe continuation rows or conflict. Coach Notes in a separate `Notes` column do not block writes to an empty RPE-adjacent Set Log cell.

Before every write (new log, edit, or delete), the app reads the current cell value and verifies it matches expectations (empty for new writes; previously-written value for edits/deletes). If verification fails — because a header was renamed, a row was inserted, or the coach edited the cell — the write is aborted and the athlete is warned. The app never guesses or overwrites unexpected content.

For a pending-write flush batch, the app may reuse one freshly fetched grid snapshot per Block tab and apply each successful write to that in-memory snapshot before resolving the next queued write. This reduces redundant fetches while preserving dynamic targeting: targets are still resolved from semantic anchors at flush time, and raw cell addresses are never persisted across syncs or app launches.

**Consequence**: if the coach renames a column header (e.g. "Notes" → "Athlete Log"), the app cannot locate the write target and will surface a warning until the next sync resolves the mismatch. This is the correct safe failure mode.

**Considered alternative**: cache raw cell addresses (e.g. "Block 27 · J15") at first write. Simpler to implement but silently corrupts data after any structural change — unacceptable given the coach actively edits the sheet.
