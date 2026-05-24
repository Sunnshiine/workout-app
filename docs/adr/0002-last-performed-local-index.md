# Local index for Last Performed lookups

Athletes need a "last time you did this" reference per Exercise while mid-workout. The naive approach — scanning backwards through Sheet tabs on demand — is too slow and requires network access at the moment of display.

We maintain a local `last_performed` index: a dictionary mapping exercise name to its most recent Set Log (block, week, day, result), skipping over any Skipped occurrences. The index is built by fetching Block tabs backwards from the current one, stopping once every Exercise in the current Block has an entry. It is persisted locally and updated incrementally as the athlete logs new sets.

This means only the current Block and however many previous Blocks are needed to cover all exercises are ever fetched — typically 1–2 Blocks back for stable programs. The worst case (a brand-new exercise with no history) results in a full backwards scan done once, asynchronously, not blocking the UI.

**Considered alternative:** Fetch all 27 Blocks on first launch and build the index from full history. Simpler logic but unnecessary data transfer for a reference that rarely goes back more than 1–2 Blocks.
