# Workout App glossary: Timed Sets

Part of the domain glossary in [CONTEXT.md](../../CONTEXT.md), which indexes every term. These
terms lean on the Logging terms in [logging.md](logging.md).

### Timed Sets

**Opening Hold**: A hold at the start of each Set of an Exercise, prescribed in its Coach Note as a duration that "hold" or "iso" governs ("Start w/ 10 sec hold, proceed to rep range" holds 10 s; "Iso 10s at the top" and "Rest 60 sec hold 20 sec" hold 10 s and 20 s). Read from the Coach Note each time and never stored. A duration the note ties to each rep, to the bottom of a rep, to the time between Sets, to the last rep, or to one named Set is none ("rest 90 sec", "3 sec hold at the bottom", "10 sec hold after your final rep", "On the last set, hold 30 sec"), and a Cadence is never a duration. When a note writes several, the first wins. Avoid: isometric hold, pre-hold, hold time.

**Timed Set**: A Set whose Prescribed Reps is a duration rather than a rep count ("40 sec", "1 min 30 sec", "0:45", "30-45 s", low end first, or 40 with a double prime). It has no rep target, so its Load Suggestion is what it was when the app read the cell as uninterpreted text. Avoid: duration set, time-based set.

**Timed Effort**: The one timed part of a Set the Set card counts: the Exercise's Opening Hold, else the Set's own Timed Set duration, else none. Offered on every Pending Set the card logs. Avoid: timed hold.

**Lead-in**: The five seconds an Effort Countdown counts down out loud before the Timed Effort begins, so the athlete who tapped has time to get their hands on the machine. Fixed, with no setting (ADR-0023). Avoid: get-ready, prep time.

**Effort Countdown**: The count one tap on the Set card starts: the Lead-in, then the Timed Effort's seconds, each cue spoken and felt so an athlete with their hands on the machine follows it without looking ("5" to "1", "Hold" or "Go", the last three seconds, then "Done" or "Time"). Starting one ends a rest still running. Logging, skipping, or moving the card off its Set, pressing the mic, leaving the Session screen, or a tap on it ends it, and so does a write or a sync that leaves its Set no longer Pending or changes its Timed Effort, by its next cue at the latest. Never stored and never written to the Sheet (ADR-0023). Avoid: hold timer, interval timer.
