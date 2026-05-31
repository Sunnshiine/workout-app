# Workout App

A mobile client for powerlifting athletes that surfaces and logs workouts from a coach-managed Google Sheet. The Sheet is the single source of truth; the app is a read-write client with a local cache.

## Language

### Program Structure

**Block**: A distinct training phase occupying one tab in the Sheet. Each Block spans 4 weeks with 4 training days per week (16 Sessions total). Blocks are numbered sequentially. Avoid: phase, cycle, mesocycle.

**Partially Uploaded Block**: A Block in which at least one Session is an Unavailable Session — the coach has populated some Sessions but not yet all 16. A normal, expected state, not an error: the athlete works the Available Sessions while the rest remain to be uploaded. Availability is decided per Session, so populated Sessions need not be contiguous (e.g. Day 1 of every Week can be Available while Days 2–4 of later Weeks are not). Avoid: incomplete block, draft block, unfinished block.

**Week**: One of four consecutive 7-day windows within a Block. Represented as a row-section in the Sheet tab. Avoid: microcycle.

**Session**: A single training day within a Block — one of Day 1–4 in a given Week. The atomic unit the athlete plans around ("what am I doing today?"). Avoid: workout, training day, day.

**Available Session**: A Session that has at least one Exercise — the athlete can open it and log. The state of any Session the coach has populated. Availability is determined per Session from whether it holds Exercises, independently of any other Session. Avoid: open session, ready session, unlocked session.

**Unavailable Session**: A Session the coach has not yet populated, holding zero Exercises. Visible in the Block grid as a clearly non-interactive tile so the athlete sees the Session exists but cannot open it. Becomes an Available Session automatically once the coach uploads its Exercises and the app next syncs — no athlete action unlocks it. Avoid: locked session, empty session, missing session, disabled session.

**Exercise**: A movement in a Session, identified by name (optionally prefixed with a tempo notation, e.g. "2-3:1:0 BB RDL"). Each Exercise has one or more prescribed Sets; each Set occupies its own row in the Sheet. Avoid: lift, movement.

**Set**: A single row in the Sheet under an Exercise, representing one prescribed set. The row carries the set's parameters (reps, load) and is where the athlete logs their actual result. Avoid: working set.

### Load & Intensity

**Training Max**: The coach's derived working weight for Squat, Bench Press, or Deadlift — calculated from the athlete's estimated 1RM. Stored per Block. Avoid: 1RM, working max.

**Prescribed Load**: The coach's intensity instruction for a given Set (e.g. "RPE6", "Drop 17.5%", "BW"). Read-only from the athlete's perspective. Avoid: target load.

**RPE** (Rate of Perceived Exertion): A 1–10 scale of effort, valid in whole-point and half-point increments (e.g. 6, 6.5, 7). Used prescriptively ("RPE6" = end set 4 reps from failure) and as athlete feedback in Last Set RPE. Distinct from %1RM, which is a separate column.

### Logging

**Set Log**: The athlete's record for a single Set, in the format `{weight}x{reps}@{RPE}` (e.g. "185x7@6"). `{weight}` is either a number in lbs or the literal "BW" for bodyweight sets (e.g. "BWx12@7"); BW is pre-filled when the coach prescribes bodyweight but always overridable with a number for weighted variations. Written per-set into the athlete Set Log column, resolved per Day as the column immediately right of `Last set RPE`. In Days where that column is also `Notes`, compact Exercise layouts may write Set 1 to the Exercise header cell only when that cell is empty or already contains the expected app-written Set 1 value. In Days where `Notes` is a separate column, Coach Notes still live in `Notes` and athlete logs live in the RPE-adjacent Set Log column. Avoid: actual load, log entry.

**Unstructured Set Log**: Non-empty athlete text on a Set row that marks that Set Logged but does not parse as a structured Set Log. It is Set-level completion evidence, distinct from a Legacy Log, and may be overwritten by a structured Set Log when the athlete corrects it. Avoid: completed from sheet, legacy log, already logged.

**Load Suggestion**: A calculated weight hint pre-filled in the set weight input, derived from the coach's prescription. Two sources: (1) "Drop X%" — computed from the previous set's logged weight once the athlete has logged it; (2) "%1RM" — computed from the Block's Training Max. Always overridable. Avoid: recommended weight, auto-fill.

**Last Set RPE**: The RPE the athlete reports for the final Set of an Exercise. Stored in the dynamically resolved `Last set RPE` column -- the app extracts it from the last Set Log and writes it there automatically. Avoid: actual RPE.

**Coach Note**: Instruction-shaped text the coach places in the `Notes` role column on the Exercise header row -- e.g. "Start w/ 10 sec hold, proceed to rep range" or "Superset w/...". Read-only to the athlete. Never overwritten by the app. When `Notes` and the athlete Set Log column are the same physical column, an empty header cell can be used for Set 1; any non-empty instruction-shaped value keeps the header reserved as a Coach Note. Avoid: set log, legacy log, athlete note.

**Legacy Log**: Result-shaped athlete text from older exercise-level logging habits — e.g. "70@10, 55", "55x8, 60x7@9.5", or "70, 80, 90x6". Counts all prescribed Sets for that Exercise as complete and can serve as Last Performed evidence when structured continuation-row Set Logs are absent; completion summaries and history display the raw entered text. It is not a Coach Note and is not a structured Set Log unless intentionally migrated into Set continuation rows. Avoid: legacy anchor result, header notes, coach note, current log.

**Set State**: The status of a single Set — Pending (not yet logged or skipped), Logged (a Set Log or Unstructured Set Log on the Set row), or Skipped (athlete explicitly marked that Set skipped; "skip" written to the sheet so the coach can see it). Skipping is Set-level; an Exercise is complete when all prescribed Sets are Logged or Skipped, or when a Legacy Log completes the Exercise. Avoid: done, missed, incomplete.

**Superset**: An athlete-created pairing of exactly two Exercises in the Current Session, used to alternate between their remaining Pending Sets while both Exercises still have pending work. Default Superset progression alternates by each Exercise's pending Set order, but the athlete can manually focus either Exercise's next Pending Set inside the Superset. Logged and Skipped Sets do not participate in Superset progression. Only Exercises with at least one Pending Set can enter a Superset. A Superset may be created before either Exercise is in focus; it becomes active when normal Set progression reaches either paired Exercise, and dissolves either when manually dismissed or as soon as either Exercise has no Pending Sets. Once dissolved, a Superset must be created again intentionally. Each Exercise can belong to at most one Superset, and each Set remains part of its original Exercise. Avoid: block, group, circuit, paired workout.

**Open Exercise**: An Exercise with at least one Pending Set in any Session belonging to the Current Week. Surfaced by the app as a makeup queue. Abandoned (no longer surfaced) the moment the athlete starts any Session in the next Week — makeups only exist within a week boundary. Avoid: deferred exercise, incomplete set.

**Makeup Day**: An informal extra gym visit within the Current Week, used to complete Open Exercises from Days 1–4. Not a distinct Session column in the sheet — makeup exercises are logged back into their original Day's column. Avoid: bonus day, extra session.

**Cadence**: The tempo prefix on an exercise name encoding eccentric, pause, and concentric durations (e.g. "2-3:1:0" in "2-3:1:0 BB RDL"). Prescribed by the coach; displayed in the UI but stripped for fallback index lookups. Avoid: tempo.

**Last Performed**: The most recent Logged result or Legacy Log for a given Exercise across all past Sessions. Displayed as a reference when the athlete views that Exercise in the Current Session; Legacy Logs are shown as their raw entered text rather than normalized into structured Set Log format. Lookup is two-tier: (1) match full exercise name including Cadence; (2) if no result, strip Cadence and match base name. If any occurrence was Skipped, continue backwards until completion evidence is found. Backed by a local index so the lookup is instant. Avoid: personal record, previous result, history.

**Performance History**: A historical view of an Exercise's prior logged performances across Sessions, used to understand progress over time. Distinct from Last Performed, which is only the single most recent Logged result. Avoid: Last Performed, previous result.

### Progress

**Current Session**: The most recently logged Session in the current Block — the session the athlete is actively working on. Derived from the sheet on each sync. Always an Available Session: when no Session has been logged yet it defaults to the first Available Session in Block order, never an Unavailable Session. Avoid: today's workout, active session.

**Current Week**: The Week containing the Current Session. Open Exercises are tracked only within the Current Week. Starting any Session in Week N+1 closes Week N — its Open Exercises are silently abandoned. Avoid: active week.

**Move On**: The athlete's explicit action to advance past the Current Session regardless of whether all sets are logged. Advances to the next Available Session, skipping any Unavailable Sessions in between; when no Available Session remains ahead but the Block still holds Unavailable Sessions, Move On returns the athlete to the Block grid instead of advancing. Offered whenever any Session — Available or Unavailable — lies ahead in the Block. Any remaining Open Exercises stay surfaced until logged or skipped. Avoid: Finish Session, Complete.

**Move On Celebration**: The athlete-facing acknowledgement shown after the athlete chooses Move On to close the Current Session. The celebration can be enhanced when every Set in the Session is Logged or Skipped, but Set completion alone does not close the Session or advance to the next Session. Avoid: workout completion, finish celebration.
