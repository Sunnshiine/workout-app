# Domain Glossary

The exact vocabulary of the app. Use these words in UI copy and design annotations; the "Avoid" words are banned in the product.

## Program structure

- **Block** — a distinct training phase, 4 Weeks long, numbered sequentially. Avoid: phase, cycle, mesocycle.
- **Partially Uploaded Block** — a Block where the coach has populated some Sessions but not all. Normal and expected, not an error; populated Sessions need not be contiguous. Avoid: incomplete/draft/unfinished block.
- **Week** — one of four consecutive weeks in a Block, holding 2–6 Sessions (the coach's template decides; commonly 3 or 4). Avoid: microcycle.
- **Session** — a single training day (Day 1–N of a Week). The atomic unit the athlete plans around: "what am I doing today?" Avoid: workout, training day, day.
- **Available Session** — has at least one Exercise; the athlete can open it and log.
- **Unavailable Session** — not yet populated by the coach. Visible in the Block grid as a clearly non-interactive tile labeled "Not uploaded"; becomes Available automatically when the coach uploads it. No athlete action unlocks it. Avoid: locked, empty, missing, disabled.
- **Exercise** — a movement in a Session, identified by name, optionally prefixed with a tempo notation ("2-3:1:0 BB RDL"). Avoid: lift, movement.
- **Set** — one prescribed effort within an Exercise. Avoid: working set.
- **Cadence** — the tempo prefix on an Exercise name (eccentric:pause:concentric, e.g. "2-3:1:0"). Displayed in the UI.

## Load & intensity

- **Training Max** — the coach's derived working weight for Squat, Bench, or Deadlift, stored per Block. Avoid: 1RM, working max.
- **Prescribed Load** — the coach's intensity instruction for a Set: "RPE6", "Drop 17.5%", "BW", "72.5%". Read-only to the athlete. Avoid: target load.
- **RPE** — Rate of Perceived Exertion, 1–10 in whole and half points. Prescriptive ("RPE6" = end 4 reps from failure) and as feedback (Last Set RPE).
- **Load Suggestion** — a calculated weight hint pre-filled in the weight input, from "Drop X%" (off the previous set) or "%1RM" (off the Training Max). Always overridable. Avoid: recommended weight, auto-fill.

## Logging

- **Set Log** — the athlete's record for one Set: `{weight}x{reps}@{RPE}`, e.g. "185x7@6"; weight is lbs or literal "BW" for bodyweight. Avoid: actual load, log entry.
- **Last Set RPE** — the RPE reported for the final Set of an Exercise; extracted automatically.
- **Coach Note** — instruction text from the coach on an Exercise ("Start w/ 10 sec hold…", "Superset w/…"). Read-only, never overwritten.
- **Set State** — Pending, Logged, or Skipped. Skipping is per-Set and explicit ("skip" is visible to the coach). An Exercise is complete when all its Sets are Logged or Skipped. Avoid: done, missed, incomplete.
- **Last Performed** — the most recent completion evidence for an Exercise across past Sessions, shown as every Set of that performance in order ("70x8@8, 75x8@9.5") so the athlete can read how it progressed and pick a starting weight. Avoid: personal record, previous result, history.
- **Performance History** — the longer view: an Exercise's prior performances across Sessions over time. Distinct from Last Performed (single most recent).

## Progress

- **Current Session** — the Session the athlete is actively working; always an Available Session. Avoid: today's workout, active session.
- **Current Week** — the Week containing the Current Session. Starting any Session in the next Week closes it.
- **Open Exercise** — an Exercise with pending Sets anywhere in the Current Week; surfaced as a makeup queue until the Week closes. Avoid: deferred exercise.
- **Makeup Day** — an informal extra gym visit within the Week to finish Open Exercises; not a distinct Session.
- **Superset** — an athlete-created pairing of exactly two Exercises, alternating their remaining Pending Sets. Dissolves when either Exercise runs out of Pending Sets. Avoid: circuit, group, paired workout.
- **Move On** — the athlete's explicit action to advance past the Current Session, complete or not. Remaining Open Exercises stay surfaced. Avoid: Finish Session, Complete.
- **Move On Celebration** — the acknowledgement shown after Move On. Can be richer when every Set is Logged/Skipped, but completion alone never closes a Session. Avoid: workout completion, finish celebration.
