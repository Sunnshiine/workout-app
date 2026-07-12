# Current App — Reference Only

How the app is structured today. This is context for the redesign, **not a constraint**: layouts, palette, and component shapes are all open to change. Interaction structure that has proven itself is noted where relevant.

## Current visual direction (being redesigned)

- Deep-green-and-black "training cockpit" dark mode with a mint action color; a softened "Sage Light" cream-sage light mode.
- Full-screen vertical background gradients; tonal layering with 1px strokes and selective iOS "Liquid Glass" surfaces instead of shadows.
- Compact radii: 16px cards, 8px controls/pills, capsule icon buttons.
- Accent color reserved strictly for the current action, selected state, and real progress ("mint means current").

## Current structure that works (worth understanding before departing)

- **The Session is a stage, not a list.** One Exercise (or one Superset) is on screen at a time: position label, Exercise name, Coach Note, a row of Set dots, a quiet one-line Last Performed reference, and the Active Set Card. The rest of the Session lives in a queue bottom-sheet (medium detent) opened from an "Up next" bar + "N of M" button at the foot of the stage. This "one thing on stage" idea came from real gym use — the athlete wants the next action, not the whole plan.
- **The Active Set Card is the signature component**: "Up next" label, Set ordinal, Exercise name, Weight/Reps/RPE value pills, and a full-width Log button whose label previews the exact Set Log about to be written (e.g. "Log 185x7@6").
- **Weight/Reps edit in place** inside their pills; RPE picks from chips. Tapping inert background dismisses transient editing.
- **Hold-to-skip**: skipping a Set is a press-and-hold with a red progress fill — deliberate, not a stray tap.
- **Block grid**: 4 Week rows × 2–6 Session tiles with distinct complete / incomplete / current / unavailable ("Not uploaded") states.
- **Move On Celebration**: a quiet full-screen moment — a rotating motivational quote in a bounded region, a saved/open-Sets line, one Sets/Exercises/Left stats row, "Tap anywhere to continue". Deliberately restrained: no confetti, badges, or mascots.
- **Settings** own manual sync ("Sync now") and appearance; the Session screen shows sync state honestly but never asks the athlete to manage sync.

## Durable copy rules

- Use exact domain words: Session, Exercise, Set, Set Log, Move On, Last Performed (see `domain-glossary.md`).
- Don't derive "X days left"-style copy from assumptions — Weeks have 2–6 Sessions, set by the coach.
- Numbers stay plain: loads, reps, RPE, and Set counts in direct native type.
