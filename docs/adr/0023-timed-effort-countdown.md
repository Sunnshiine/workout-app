# ADR 0023: The app reads a timed effort from the coach's text and counts it out loud

**Status:** Accepted
**Date:** 2026-10-30

## Context

An athlete holding an isometric counts the seconds in their head, because their hands are on the
machine. The coach already writes the hold, in the Coach Note ("Start w/ 15 sec hold at the top,
and then proceed into leg ext. at prescribed cadence") or as the Reps cell itself ("40 sec"). The
app read neither. Prescribed Reps called "40 sec" text it does not interpret. A Coach Note also
holds durations that are not holds ("rest 90 sec") and digits that are not durations: a Cadence
("0:5:0") and a rep pyramid ("1-2-3-3-2-1").

## Decision

- **One parser reads every duration.** `EffortDuration` reads a count with a unit (s, sec,
  second, min, minute) or a clock (`1:30`, `:45`). A range reads as its low end, and both ends must
  resolve, low first. A duration runs from 1 s to 60 min in whole seconds. A match that touches
  another digit or a colon, or a dash joined to a digit before it, is part of a Cadence or a
  pyramid, and is no duration.
- **An Opening Hold comes from the Coach Note only when the note ties a duration to a hold at
  the start.** The duration has to sit beside "hold" or "iso", and its clause must not name each,
  every, per, between, after, last, or finish. So "rest 90 sec" and "10 sec hold after your final
  rep" give none. When a note writes several holds, the first wins. The parser misses rather than
  guesses. A missed hold leaves the athlete counting, as they do today, and a false one puts a
  wrong count on the card.
- **A Reps cell that is a duration makes the Set a Timed Set.** `PrescribedReps` gains a timed
  case. It has no rep target, so the Load Suggestion and everything else that reads the target are
  unchanged.
- **One Timed Effort per Set.** That is the Opening Hold, else the Timed Set, else none. It is
  derived each time from the cells and never stored, because the Sheet is the source of truth
  (ADR-0001).
- **One tap counts it.** The Set card offers the Timed Effort on every Pending Set it logs. One tap
  starts a fixed five-second Lead-in and then counts the effort down. There is no setting, no
  "start now", and no listening mic. `EffortCountdown` keeps time on the same expiry scheduler as
  `RestTimer`, with an injected clock. A wake that comes late plays only the latest cue due, so
  the voice says where the count is now instead of the seconds it missed.
- **Every cue is spoken and felt.** The Lead-in says 5 to 1, with a light tap on each. The effort
  begins on "Hold" or "Go" with a firmer tap. Its last three seconds are counted, and it ends on
  "Done" or "Time" with the rest timer's expiry buzz. `SpokenCountdownCues` speaks through the
  playback category in voice-prompt mode, ducking the athlete's music, so it sounds with the silent
  switch on. It holds the audio session only while it speaks and 1.5 s after.
- **The countdown belongs to its Set.** A run is keyed by Session Coordinate and the Set's place
  in its Session, so a sync's re-parse keeps it. Starting one ends a rest still running. Logging,
  skipping, a focus change, another Session, Move On, the mic, leaving the Session screen, or a tap
  ends it.

## Considered alternatives

- **A setting for the Lead-in, or a toggle for the feature.** Rejected. The operator asked for one
  tap that always does the same thing.
- **Start the count by voice.** Rejected. It needs a mic listening between Sets, which costs battery
  and privacy and contends with Dictation for the audio session.
- **Read any duration in the Coach Note as the hold.** Rejected. "rest 90 sec" would count a rest
  as a hold.

## Consequences

- No one has heard the ducking, the silent switch, or Dictation right after a cue on a device. The
  simulator proves the count, the cues' timing, and the card.
- A coach who words a hold another way gets no control until the parser learns the phrasing, with
  a test row for it.
