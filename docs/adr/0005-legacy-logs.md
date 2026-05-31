# Legacy logs are completion evidence

Older manually-entered athlete results can appear in the Exercise header Notes cell, even though the current write model protects instruction-shaped header Notes as Coach Notes and usually writes structured Set Logs to continuation rows. We treat comma-style or otherwise legacy-shaped header Notes as Legacy Logs: they count all prescribed Sets for that Exercise as complete and can serve as Last Performed evidence when structured Set Logs are absent. A single structured app-format Set Log or `skip` marker on a compact Exercise header row is not a Legacy Log; it is Set 1's Set-level state.

The app must keep instruction-shaped header Notes as Coach Notes, must not automatically migrate or overwrite legacy header results, and must prefer structured Set Logs whenever both forms exist. This preserves historical manual logs without confusing them with coach instructions or inventing structured per-set data that the sheet does not contain.
