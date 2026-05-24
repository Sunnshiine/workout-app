# Workout App

A mobile client for powerlifting athletes that surfaces and logs workouts from a coach-managed Google Sheet. The Sheet is the single source of truth; the app is a read-write client with a local cache.

## Language

### Program Structure

**Block**: A distinct training phase occupying one tab in the Sheet. Each Block spans 4 weeks with 4 training days per week (16 Sessions total). Blocks are numbered sequentially. Avoid: phase, cycle, mesocycle.

**Week**: One of four consecutive 7-day windows within a Block. Represented as a row-section in the Sheet tab. Avoid: microcycle.

**Session**: A single training day within a Block — one of Day 1–4 in a given Week. The atomic unit the athlete plans around ("what am I doing today?"). Avoid: workout, training day, day.

**Exercise**: A movement in a Session, identified by name (optionally prefixed with a tempo notation, e.g. "2-3:1:0 BB RDL"). Each Exercise has one or more prescribed Sets; each Set occupies its own row in the Sheet. Avoid: lift, movement.

**Set**: A single row in the Sheet under an Exercise, representing one prescribed set. The row carries the set's parameters (reps, load) and is where the athlete logs their actual result. Avoid: working set.

### Load & Intensity

**Training Max**: The coach's derived working weight for Squat, Bench Press, or Deadlift — calculated from the athlete's estimated 1RM. Stored per Block. Avoid: 1RM, working max.

**Prescribed Load**: The coach's intensity instruction for a given Set (e.g. "RPE6", "Drop 17.5%", "BW"). Read-only from the athlete's perspective. Avoid: target load.

**RPE** (Rate of Perceived Exertion): A 1–10 scale of effort. Used prescriptively ("RPE6" = end set 4 reps from failure) and as athlete feedback in Last Set RPE. Distinct from %1RM, which is a separate column.

### Logging

**Set Log**: The athlete's record for a single Set, in the format `{weight}x{reps}@{RPE}` (e.g. "185x7@6"). `{weight}` is either a number in lbs or the literal "BW" for bodyweight sets (e.g. "BWx12@7"); BW is pre-filled when the coach prescribes bodyweight but always overridable with a number for weighted variations. Written per-set into the Notes column (J) on the Set's continuation row — never on the Exercise header row, which is reserved for Coach Notes. Avoid: actual load, log entry.

**Load Suggestion**: A calculated weight hint pre-filled in the set weight input, derived from the coach's prescription. Two sources: (1) "Drop X%" — computed from the previous set's logged weight once the athlete has logged it; (2) "%1RM" — computed from the Block's Training Max. Always overridable. Avoid: recommended weight, auto-fill.

**Last Set RPE**: The RPE the athlete reports for the final Set of an Exercise. Stored in column I — the app extracts it from the last Set Log and writes it there automatically. Avoid: actual RPE.

**Coach Note**: Instructional text the coach places in the Notes column (J) on the Exercise header row — e.g. "Start w/ 10 sec hold, proceed to rep range". Read-only to the athlete. Never overwritten by the app.

**Set State**: The status of a single Set — Pending (not yet logged or skipped), Logged (has a Set Log), or Skipped (athlete explicitly marked it skipped; "skip" written to the sheet so the coach can see it). Avoid: done, missed, incomplete.

**Open Exercise**: An Exercise with at least one Pending Set in any Session belonging to the Current Week. Surfaced by the app as a makeup queue. Abandoned (no longer surfaced) the moment the athlete starts any Session in the next Week — makeups only exist within a week boundary. Avoid: deferred exercise, incomplete set.

**Makeup Day**: An informal extra gym visit within the Current Week, used to complete Open Exercises from Days 1–4. Not a distinct Session column in the sheet — makeup exercises are logged back into their original Day's column. Avoid: bonus day, extra session.

**Cadence**: The tempo prefix on an exercise name encoding eccentric, pause, and concentric durations (e.g. "2-3:1:0" in "2-3:1:0 BB RDL"). Prescribed by the coach; displayed in the UI but stripped for fallback index lookups. Avoid: tempo.

**Last Performed**: The most recent Logged result for a given Exercise across all past Sessions. Displayed as a reference when the athlete views that Exercise in the Current Session. Lookup is two-tier: (1) match full exercise name including Cadence; (2) if no result, strip Cadence and match base name. If any occurrence was Skipped, continue backwards until a Logged result is found. Backed by a local index so the lookup is instant. Avoid: personal record, previous result, history.

### Progress

**Current Session**: The most recently logged Session in the current Block — the session the athlete is actively working on. Derived from the sheet on each sync. Avoid: today's workout, active session.

**Current Week**: The Week containing the Current Session. Open Exercises are tracked only within the Current Week. Starting any Session in Week N+1 closes Week N — its Open Exercises are silently abandoned. Avoid: active week.

**Move On**: The athlete's explicit action to advance past the Current Session regardless of whether all sets are logged. Any remaining Open Exercises stay surfaced until logged or skipped. Avoid: Finish Session, Complete.
