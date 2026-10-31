# Workout App

A mobile client for powerlifting athletes that surfaces and logs workouts from a coach-managed Google Sheet. The Sheet is the single source of truth; the app is a read-write client with a local cache.

## Language

### Program Structure

**Block**: A distinct training phase occupying one tab in the Sheet. Each Block spans 4 weeks; a Week holds 2–6 training days (the coach's template decides — commonly 3 or 4), so a Block has 8–24 Sessions. Blocks are numbered sequentially. Avoid: phase, cycle, mesocycle.

**Partially Uploaded Block**: A Block in which at least one Session is an Unavailable Session — the coach has populated some Sessions but not yet all of them. A normal, expected state, not an error: the athlete works the Available Sessions while the rest remain to be uploaded. Availability is decided per Session, so populated Sessions need not be contiguous (e.g. Day 1 of every Week can be Available while Days 2–N of later Weeks are not). Avoid: incomplete block, draft block, unfinished block.

**Week**: One of four consecutive 7-day windows within a Block. Represented as a row-section in the Sheet tab. Avoid: microcycle.

**Session**: A single training day within a Block, one of the 2–6 a Week holds (set by the coach's template). Its Day number is the N of its `Day N` header in the Sheet, from 1 to 7 and used once per Week, so a Week can skip a number. The atomic unit the athlete plans around ("what am I doing today?"). Its Week number and Day number together identify it, and the app stores that pair wherever it remembers a Session, so renumbering Days is a migration. Avoid: workout, training day, day.

**Session Address**: Which Session within one Block, as its Week number and Day number. Written `w1d3` by the `workout` CLI and `W1 D3` in the Exercise History gutter. It carries no Block tab, so it re-resolves against whichever Block is cached. Live Session state, queued writes, Exercise History, and CLI addresses hold one; the cached Block and the parsed Sheet keep one number per level and pair them into an address. A write queued by an older build can hold a Day that counts header position instead of the header's N, and its Day numbering says which. Avoid: session key, week/day pair, session index.

**Available Session**: A Session that has at least one Exercise — the athlete can open it and log. The state of any Session the coach has populated. Availability is determined per Session from whether it holds Exercises, independently of any other Session. Avoid: open session, ready session, unlocked session.

**Unavailable Session**: A Session the coach has not yet populated, holding zero Exercises. Visible in the Block grid as a clearly non-interactive tile so the athlete sees the Session exists but cannot open it. Becomes an Available Session automatically once the coach uploads its Exercises and the app next syncs — no athlete action unlocks it. Avoid: locked session, empty session, missing session, disabled session.

**Exercise**: A named entry in a Session (optionally prefixed with a tempo notation, e.g. "2-3:1:0 BB RDL"). Each Exercise has one or more prescribed Sets, authored across one or more Prescription Lines. Distinct from Movement, the cross-Session identity that several spellings of the same name can share. Avoid: lift, which names only the three Main Lifts.

**Prescription Line**: One prescription row of an Exercise, carrying its own Sets/Reps/Load and its own comma-separated Set Logs in its Notes cell. Most Exercises are a single Line (the anchor row, whose Sets cell is the total — e.g. Kevin's template). Some coaches (e.g. J. Alarcon) stack several Lines per Exercise: the anchor row plus blank-name continuation rows that each have their own numeric Sets cell. An Exercise's Set count is the sum of its Lines' Sets. When a Line's Notes cell holds a Coach Note, that Line's Set Logs move to a Visible Writable Row in the same Exercise that is not itself a Line. Avoid: set group, sub-exercise, row.

**Set**: One prescribed effort within an Exercise. A single Prescription Line may represent multiple Sets, and the app writes that Line's Set Logs into its row as comma-separated values. Avoid: working set.

**Visible Writable Row**: A row that is not hidden by the user or by a filter, within the current Session's Sheet section, where the app may write athlete Set Logs without crossing into another Session or overwriting coach-authored content. For Exercises whose header Notes cell is occupied by a Coach Note, Set Logs must move only to a Visible Writable Row inside that same Session. Avoid: spacer row, hidden row workaround, fallback row.

### Load & Intensity

**Main Lift**: One of the three barbell lifts a Training Max is defined for — Squat, Bench Press, Deadlift. A closed set: the Sheet's Training Max header area holds exactly these three labelled rows, and an Exercise claims at most one of them by lowercased substring on its Cadence-stripped base name, squat before bench before deadlift ("Front Squat" claims squat; "RDL" claims none). Far stricter than Movement, the fuzzy cross-Session identity (ADR-0013), which is deliberately not used here. "Lift" names this closed set and nothing else — a named entry in a Session is still an Exercise. Avoid: main movement, big three, competition lift.

**Training Max**: The coach's derived working weight for a Main Lift — calculated from the athlete's estimated 1RM. Stored per Block. Avoid: 1RM, working max.

**Prescription**: What the coach asked of one Set: its Prescribed Reps, its Prescribed Load, and its %1RM, read once from those three cells of its Prescription Line. It is derived from the cells each time and never stored, so the Sheet stays the source of truth, and the card's prescription text still shows the cells as the coach typed them. Distinct from Prescription Line, the Sheet row that carries the cells. Avoid: plan, programming.

**Prescribed Reps**: The coach's Reps cell for a Set. It is exactly one of three things: a rep target, either one whole number ("5") or a range whose ends both resolve, low end first ("8-10", "7 – 8"); a duration, which makes the Set a Timed Set ("40 sec", "0:45"); or text the app does not interpret ("AMRAP", "5+", "1-2-3-3-2-1"). Avoid: target reps, rep goal.

**Prescribed Load**: The coach's intensity instruction for a given Set. It is exactly one of four things: bodyweight ("BW"), a Drop of a share off the previous Set's weight ("Drop 17.5%"), an RPE target on one of the ten RPE points ("RPE6"), or text the app does not interpret ("Start conservative", "RPE 5.5"). The %1RM is its own column, not a Prescribed Load. Read-only from the athlete's perspective. Avoid: target load.

**RPE** (Rate of Perceived Exertion): One of ten points of effort: 5, 6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10. A `{weight}x{reps}@{RPE}` token whose RPE is any other number is not a Set Log, so the app keeps it as the text it was entered as. Used prescriptively ("RPE6" = end set 4 reps from failure) and as athlete feedback in Last Set RPE. Distinct from %1RM, which is a separate column.

### Logging

Checking a name against the avoid-lists, or using a Logging term: read
[docs/context/logging.md](docs/context/logging.md), where each Logging term's definition and
avoid-list lives and binds as the rest of this glossary does. A new Logging term goes there, with its name added here.

**Set Log**, **Unstructured Set Log**, **Load Suggestion**, **RPE Table**, **Estimated Single**, **Load Basis**, **Last Set RPE**, **Coach Note**, **Legacy Log**, **Header Notes Role**, **Completion Evidence**, **Set State**, **Superset**, **Open Exercise**, **Makeup Day**, **Cadence**, **Entered Name**, **Exercise Reference**, **Base Name**, **Last Performed**, **Exercise History** (and its **entry**), **Session Coordinate**, **Detached Session**, **Exercise History fill**, **Movement**, **Opening Hold**, **Timed Set**, **Timed Effort**, **Lead-in**, and **Effort Countdown**.

### Dictation

The terms for logging a Set by speech live in
[docs/context/dictation.md](docs/context/dictation.md), where each one's definition and avoid-list
binds as the rest of this glossary does. A new Dictation term goes there, with its name added
here.

**Spoken Set**, **Dictation**, **Live Transcript**, **Recording Transcript**, **Pause**, **Speech Model**, **Decision Deadline**, **Dictation Record**

### Progress

**Current Session**: The session the athlete is actively working on in the current Block: the Current Session Pin while one is in force, otherwise the most recently logged Session, derived from the sheet on each sync. Always an Available Session: when no Session has been logged yet it defaults to the first Available Session in Block order, never an Unavailable Session. Avoid: today's workout, active session.

**Current Session Pin**: The Session the athlete last advanced to with Move On or chose with the off-live-edge Make current control, held on the device for each Block tab and never written to the Sheet. It wins over Sheet-derived progress, even behind the most recently logged Session, while it still names an Available Session of that Block; when it names none, as after a re-parse, Sheet-derived progress wins without telling the athlete. Only a Make current pin is an override, because a Move On moves along the Block rather than away from it. Avoid: manual override, advanced-to order, manual current session.

**Current Week**: The Week containing the Current Session. Open Exercises are tracked only within the Current Week. Starting any Session in Week N+1 closes Week N — its Open Exercises are silently abandoned. Avoid: active week.

**Move On**: The athlete's explicit action to advance past the Current Session regardless of whether all sets are logged. Advances to the next Available Session, skipping any Unavailable Sessions in between; when no Available Session remains ahead, because the rest are Unavailable or because the Current Session is the Block's last, Move On returns the athlete to the Block grid instead of advancing. Offered from every Current Session, so an athlete who finished a Block can close its last Session while the coach uploads the next. Any remaining Open Exercises stay surfaced until logged or skipped. Avoid: Finish Session, Complete.

**Move On Celebration**: The athlete-facing acknowledgement shown after the athlete chooses Move On to close the Current Session. The celebration can be enhanced when every Set in the Session is Logged or Skipped, but Set completion alone does not close the Session or advance to the next Session. Avoid: workout completion, finish celebration.

**Viewed Session**: The Session the athlete is looking at. The Current Session by default, or any other Session they have opened from the Block grid or an Open Exercise. **Live edge**: the state of the Viewed Session being the Current Session. Move On, the Open Exercises makeup queue, and the rest Live Activity are offered only at the live edge (ADR-0011). Decided by model identity, so a second instance backing one Session is still the live edge and never ends a running rest. Avoid: displayed session, preview session, active session.

### Sync

**Sync Outcome**: What a finished sync step left the athlete to deal with, as one named result rather than one "conflict". Five of them are distinct: a Set Log the local store refused (that log is gone), a write the Sheet refused (the log is still stored and, per ADR-0003, never retried), a spreadsheet with no Block tab (a setup problem, no log at risk), a parser warning, and a stopped Exercise History fill (the last two are a successful sync with a footnote). The ordinary three are nothing to report, the Sheet unreachable, and Set Logs still queued for the next flush. Being in flight is not an outcome; that is the sync and flush depth Destructive Transition guards on. A sync reports one outcome from what its flush and its Sheet read each concluded, and a refused write is the only one a clean read leaves standing. Avoid: sync state, conflict, sync error.

**Destructive Transition**: Switching the configured Sheet, or signing out. One domain move under two names: both abandon Set Logs the athlete recorded locally that have not yet reached the Sheet. Refused while any sync or pending-write flush is running, including a background flush the athlete never asked for, because discarding those logs underneath a flush that is writing them loses work the coach would otherwise have seen. Avoid: sheet change, disconnect, reset.
