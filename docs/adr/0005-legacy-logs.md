# Legacy logs are completion evidence

Older manually-entered athlete results can appear in the Exercise header Notes cell, even though the current write model reserves header Notes for Coach Notes and writes structured Set Logs to continuation rows. We treat result-shaped header Notes as Legacy Logs: they count all prescribed Sets for that Exercise as complete and can serve as Last Performed evidence when structured continuation-row Set Logs are absent.

The app must keep instruction-shaped header Notes as Coach Notes, must not automatically migrate or overwrite legacy header results, and must prefer structured continuation-row Set Logs whenever both forms exist. This preserves historical manual logs without confusing them with coach instructions or inventing structured per-set data that the sheet does not contain.
