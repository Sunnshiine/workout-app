# Product

## Register

product

## Users

A single powerlifting athlete, training under a coach who programs their work in a Google Sheet. The athlete opens the app mid-Session, on the gym floor, between Sets: glancing down to see what is prescribed, logging what they actually did, and moving on. Their context is physical and time-sliced: hands may be chalky, attention is on the bar, and the app competes with rest timers and the next Set. The coach never touches the app; they author in the Sheet, which stays the single source of truth.

## Product Purpose

Surface the athlete's coach-programmed training and let them log Sets without friction. The Sheet is authoritative; the app is a read-write client with a local cache that makes "what am I doing today?" and "log this Set" instant, even though the data lives in a spreadsheet built for the coach, not the athlete. Success is the athlete logging every Set in the moment, trusting that it round-trips to the coach's Sheet correctly, and never thinking about the spreadsheet underneath.

## Brand Personality

A supportive training partner, not a hype machine. Encouraging and warm: it acknowledges real progress and treats the athlete as someone doing hard work worth respecting. Three words: **warm, focused, trustworthy**. The emotional goal is quiet confidence. The athlete feels accompanied and on-track, never nagged, gamified, or shouted at. Celebration is earned and occasional, tied to genuine milestones such as moving on from a Session, not sprinkled on every tap.

## Anti-references

- **Bro-y hype / aggro fitness.** No neon-on-black "beast mode," flames, aggressive all-caps shouting, or streaks-as-pressure. Warmth must never tip into gym-bro intensity.
- **Spreadsheet-in-an-app.** It is a Sheet client but must never look like one. No dense grids, tiny tap targets, raw cell editing, or visible row and column plumbing.
- **Generic fitness SaaS.** Avoid the interchangeable consumer-fitness look: uniform rounded-card grids, stock gradients, ring charts everywhere, badge spam, and cheerful clip art.
- **Over-gamified.** No XP bars, confetti on every tap, mascots, points, levels, or streak pressure.

## Design Principles

- **Log in the moment, think later.** Every screen optimizes for the athlete mid-Set: the next action is obvious and reachable, prescription and logging sit together, and nothing demands attention the bar should have.
- **Hide the spreadsheet.** The Sheet's structure is an implementation detail. The athlete sees Sessions, Exercises, Sets, and Set Logs, never plumbing.
- **Earned celebration.** Acknowledgement scales with the achievement. Finishing or moving on from a Session earns a moment; a single logged Set does not.
- **Trust the round-trip.** The athlete must feel certain their Set Logs reach the coach correctly. Surface sync state and pending writes honestly; never imply a save that has not landed.
- **Respect the athlete's expertise.** Warmth is not coddling. Show real numbers, loads, RPE, and history plainly, and trust the athlete to read them.

## Accessibility & Inclusion

No specific accessibility goals at this time.
