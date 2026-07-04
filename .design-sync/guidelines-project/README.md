# Workout App — Redesign Guidelines

This project seeds a **full UI redesign** of a native iOS app. It contains no components — design from scratch, guided by the rules below. The current app (a deep-green "training cockpit") is being redesigned; its visual system is reference material in `guidelines/current-app-reference.md`, not a constraint. What MUST survive the redesign: the domain language, the brand personality, the anti-references, and the iOS-native shape of everything.

## What the app is

A mobile client for one powerlifting athlete whose coach programs training in a Google Sheet. The athlete opens the app mid-Session on the gym floor, between Sets: glance at what's prescribed, log what they did, get back to the bar. Hands may be chalky; attention is on the bar. The coach never touches the app — the Sheet stays the source of truth, but the athlete must never feel the spreadsheet underneath.

## Design for iOS — hard constraints

- iPhone-first. Design in iPhone frames (393×852); respect safe areas and the Dynamic Island.
- Native patterns only: navigation stacks with back chevrons, bottom sheets with detents, context menus, SF Symbols-style iconography. No hamburger menus, no web-style top nav, no hover states — everything is touch.
- Typography: SF Pro / `-apple-system` system font stack. Weight carries hierarchy, not font novelty. Numbers (loads, reps, RPE) stay plain — no gradient text, outlines, or decorative tracking.
- Touch targets ≥ 44pt, one-handed reach for the primary action. Controls are large: the athlete is between heavy sets.

## Domain vocabulary — use these exact words in all UI copy

- **Block** — a 4-week training phase. (Never: phase, cycle, mesocycle)
- **Week** — one of four weeks in a Block, holding 2–6 Sessions (count set by the coach).
- **Session** — a single training day, e.g. "Week 2 · Day 3". (Never: workout, training day)
- **Exercise** — a movement in a Session, optionally tempo-prefixed, e.g. "2-3:1:0 BB RDL". (Never: lift)
- **Set** / **Set Log** — one prescribed effort; the athlete's record is `{weight}x{reps}@{RPE}`, e.g. "185x7@6" ("BW" for bodyweight).
- **RPE** — effort on a 1–10 scale, half-point steps.
- **Prescribed Load** — the coach's intensity instruction, e.g. "RPE6", "Drop 17.5%", "BW". Read-only.
- **Last Performed** — the most recent prior result for an Exercise, shown as a quiet reference (all sets, e.g. "70x8@8, 75x8@9.5").
- **Coach Note** — read-only instruction text from the coach on an Exercise.
- **Move On** — the athlete's explicit action to close the Current Session and advance. (Never: Finish Session, Complete)
- **Unavailable Session** — a Session the coach hasn't uploaded yet: visible but clearly non-interactive, labeled "Not uploaded". A normal state, not an error.
- **Superset** — an athlete-created pairing of exactly two Exercises, alternating their pending Sets.
- **Open Exercises** — unfinished Exercises from earlier Sessions in the current Week, surfaced as a makeup queue.

## Brand personality

A supportive training partner, not a hype machine. Three words: **warm, focused, trustworthy**. The emotional goal is quiet confidence — the athlete feels accompanied and on-track, never nagged, gamified, or shouted at. Celebration is earned and occasional (tied to Move On), never sprinkled on every tap. Warmth is not coddling: show real numbers, loads, RPE, and history plainly and trust the athlete to read them.

## Anti-references — never do these

- **Bro-y hype / aggro fitness**: no beast-mode copy, flames, neon-on-black aggression, all-caps shouting, or streaks-as-pressure.
- **Spreadsheet-in-an-app**: no dense grids, tiny tap targets, raw cell editing, or visible row/column plumbing.
- **Generic fitness SaaS**: no interchangeable rounded-card dashboards, stock gradients, ring charts everywhere, badge spam, or cheerful clip art.
- **Over-gamified**: no XP bars, points, levels, mascots, streak pressure, or confetti on ordinary logging taps.

## Principles that survive the redesign

- **Log in the moment, think later.** Every screen optimizes for the athlete mid-Set: the next action is obvious and reachable; prescription and logging sit together.
- **Hide the spreadsheet.** The athlete sees Sessions, Exercises, Sets, and Set Logs — never Sheet structure.
- **Earned celebration.** Acknowledgement scales with the achievement. Moving on from a Session earns a moment; a single logged Set does not.
- **Trust the round-trip.** Surface sync state and pending writes honestly; never imply a save that hasn't landed. Manual sync lives in Settings ("Sync now"), not in the Session flow.

## Screens to design

1. **Session** — the core surface. What's prescribed now; log a Set (Weight / Reps / RPE + a Log action that previews the exact Set Log); per-Set progress; the Last Performed reference; Coach Notes; access to the rest of the Session; Move On.
2. **Block grid** — 4 Weeks × 2–6 Sessions as tiles with distinct complete / incomplete / current / unavailable states.
3. **Move On Celebration** — the one large celebratory moment: a motivating quote plus a Sets / Exercises / Left stats row.
4. **Performance History** — an Exercise's past results across Sessions.
5. **Settings** — Training Sheet connection, appearance, manual "Sync now".
6. **Onboarding / empty states** — connecting to the coach's Sheet; a Block with nothing uploaded yet.

Read `guidelines/domain-glossary.md` for the full vocabulary, `guidelines/product.md` for product intent, and `guidelines/current-app-reference.md` for how the current app is structured (reference, not constraint).
