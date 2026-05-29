# Google Sheet as backend with local-first sync

The athlete's coach programs workouts in a Google Sheet and expects to keep editing it directly. The athlete needs to view and log on iOS; the gym has reliable-but-not-guaranteed connectivity.

We treat the Google Sheet as the single source of truth. The app maintains a local cache of the current Block, writing Set Logs locally first and syncing to the Sheet in the background. The app never independently owns data — everything either comes from or will be written back to the Sheet.

This keeps the coach's workflow untouched (coach edits Sheet; athlete sees changes on next sync) and avoids building a dedicated backend for a single-athlete app. Local-first protects against gym connectivity loss without requiring conflict-resolution infrastructure: the app only writes new Set Log data to verified-safe Notes cells. Continuation rows remain the common target; compact Exercise layouts may use an empty Exercise header Notes cell for Set 1, but any non-empty unexpected header value is protected from overwrite.

**Considered alternatives:**
- *Dedicated backend (e.g. Supabase):* unnecessary complexity; coach would have to export/import to keep using the Sheet.
- *Online-only writes:* simpler, but a connectivity blip mid-session corrupts the workout flow.
- *App as source of truth:* breaks the coach's review workflow entirely.
