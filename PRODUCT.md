# Product

## Register

product

## Users

A single powerlifting athlete, training under a coach who programs their work in a
Google Sheet. The athlete opens the app mid-workout, on the gym floor, between sets:
glancing down to see what's prescribed, logging what they actually did, and moving on.
Their context is physical and time-sliced — hands may be chalky, attention is on the
bar, and the app competes with rest timers and the next set. The coach never touches
the app; they author in the Sheet, which stays the single source of truth (ADR-0001).

## Product Purpose

Surface the athlete's coach-programmed training and let them log sets without friction.
The Sheet is authoritative; the app is a read-write client with a local cache that makes
"what am I doing today?" and "log this set" instant, even though the data lives in a
spreadsheet built for the coach, not the athlete. Success is the athlete logging every
set in the moment, trusting that it round-trips to the coach's Sheet correctly, and never
once thinking about the spreadsheet underneath.

## Brand Personality

A supportive training partner, not a hype machine. Encouraging and warm: it acknowledges
real progress (the Move On Celebration after closing a Session) and treats the athlete as
someone doing hard work worth respecting. Three words: **warm, focused, trustworthy**. The
emotional goal is quiet confidence — the athlete feels accompanied and on-track, never
nagged, gamified, or shouted at. Celebration is earned and occasional, tied to genuine
milestones (finishing a Session), not sprinkled on every tap.

## Anti-references

- **Bro-y hype / aggro fitness.** No neon-on-black "beast mode," flames, aggressive
  all-caps shouting, or streaks-as-pressure. Warmth must never tip into gym-bro intensity.
- **Spreadsheet-in-an-app.** It is a Sheet client but must never *look* like one — no dense
  grids, tiny tap targets, or raw cell editing. The spreadsheet is plumbing, not the UI.
- **Generic fitness SaaS.** Avoid the interchangeable consumer-fitness look: uniform
  rounded-card grids, stock gradients, ring charts everywhere, badge spam, cheerful clip-art.
- **Over-gamified.** No XP bars, confetti on every tap, mascots, or points/levels.

## Design Principles

- **Log in the moment, think later.** Every screen optimizes for the athlete mid-set:
  the next action is obvious and reachable, prescription and logging sit together, and
  nothing demands attention the bar should have.
- **Hide the spreadsheet.** The Sheet's structure (rows, columns, cells, hidden rows) is
  an implementation detail. The athlete sees Sessions, Exercises, and Sets — never plumbing.
- **Earned celebration.** Acknowledgement scales with the achievement. Finishing a Session
  earns a moment; a single logged set does not. Delight stays rare so it stays meaningful.
- **Trust the round-trip.** The athlete must feel certain their logs reach the coach
  correctly. Surface sync state and pending writes honestly; never imply a save that hasn't
  landed.
- **Respect the athlete's expertise.** Warmth is not coddling. Show real numbers (loads,
  RPE, history) plainly and trust the athlete to read them.

## Accessibility & Inclusion

No specific accessibility goals at this time.
