# Coding standards

The review standard for this repo. `CONTEXT.md`, `docs/adr/`, `PRODUCT.md`, and `DESIGN.md` win
over anything here. `.swift-format` and `.swiftlint.yml` settle formatting and every mechanical
rule, so a force unwrap, force try, or force cast in shipped code, or a font built outside the
Theme seam, is a lint error, not a finding (`Tests/.swiftlint.yml` lists what a test body may do).
A reviewer flags only what a lint does not judge, and never a preference. A rule earns a line here
when it cost this repo a shipped bug and applying it takes context a regex does not have.

Apply every rule to every hunk of the diff. For each finding, cite the rule's heading (or a Tests
bullet's lead-in) and quote the hunk. Each rule ends with the issues that earned it and, where a
fix landed, the symbol that shows it; read the symbol when the rule alone does not settle a hunk.
Verification commands are in `AGENTS.md`.

## Architecture

### The Sheet is the truth

Every write to the Sheet or the cache passes through `SyncCoordinator` and the pending-write queue
(ADR-0001, ADR-0006), and a transition that could abandon queued Set Logs asks
`canBeginDestructiveTransition` first.

Look for a write that bypasses `SyncCoordinator`, or a transition without the guard. (The guard
answered `true` during a live sync, so switching Sheets could abandon recorded Set Logs. #585,
fixed in #595.)

### Views hold no logic that needs a test

`App/Views/` is outside `Sources/`, so `swift test` cannot reach a View (ADR-0017). A guard, a
calculation, or a branch that decides behaviour lives in the library, and the View reads the
answer.

Look for a computed property on a View that ORs store state together, a `switch` on domain state
inside `body`, or a decision the `workout` CLI would need and cannot see. (Half of the
destructive-transition guard lived in `SettingsView` computed properties, #582. Now
`DestructiveTransition.canBeginDestructiveTransition`.)

### Deep modules

The deletion test decides whether a type earns its interface. If deleting the type would lose
nothing (a thin switch over prose, a pass-through), the concept it fronts is what needs a module.
The `codebase-design` skill carries the long form.

Look for a new type that only forwards, a method added where a caller could have asked a deeper
question, or a question already answered privately in a second place. (The sync outcome was a thin
switch over message strings until #514 replaced it with `SyncOutcome`. Applied again in #570 and
#572.)

## State

### One owner per fact

A fact derived from other state has exactly one place that answers it. Three shapes break this.

- A latch. A Bool that every method changing the state must remember to set. (Assigned at ten
  sites, seven of them `false`, so a new method could forget it silently. #586.)
- A mirror. A value re-derived in several places with drifting conditions. (Last Set RPE was
  decided in five places and the skip path forgot one, leaving a stale RPE in the coach's Sheet.
  #570, fixed in #574.)
- A predicate spelled twice. (Live edge was decided three times, once by object identity and twice
  by model identity. #572, fixed in #591.)

Look for the same condition in two files, a Bool assigned in more than two methods, or a comment
that explains when a combination of fields is valid. Now `WorkoutStore.view(_:)` is the only
writer of `viewedSession`, and `LiveEdge.isAtLiveEdge` answers once.

### Control signals come from what they claim

A value that gates behaviour reads the thing it claims to measure. Display state is not a control
signal.

Look for `state == .someCase` used as a guard, or a Bool that is `true` only because the last
writer set it. (`isSyncing` read the banner's display enum, which `flushPending` reset to `.idle`
mid-sync, so the destructive-transition guard opened with a sync on the wire. #585. Now
`SyncCoordinator.isSyncing` reads two in-flight counters that only their owners change, and the
banner derives from them.)

### Outcomes are enums with one case per outcome

A result type has one case per thing that can happen, carries what the step produced, and leaves
the wording to the presentation layer. Precedence between outcomes lives in one function, and a
step returns its result instead of assigning state as a side effect.

Look for a case whose payload is `[String]` fed by more than one producer,
`messages.first ?? "…"`, English composed inside a store or coordinator, or a method that sets
`state` on its way out. (`.conflict([String])` carried five different outcomes, rendered
identically. #589, #514. Now `SyncOutcome`, precedence in `SyncOutcome.sync(sheetRead:flush:)`,
and the queued count returned on `PendingWriteFlushResult.stoppedForRetry(queued:)` instead of
assigned, #598.)

## Concurrency

### Background work does not write foreground fields

A `Task` whose handle is dropped runs after its creator has moved on. A View may start one to call
a store method, which writes on the main actor. A dropped or detached task never assigns a store
field itself after the method that owns the sequence has returned, because it races the next
writer. Work whose result the sequence needs is held and awaited.

Look for `Task { … }` whose body assigns a store property, or work started after the method that
owns the state has returned. (The history backfill ran detached after `sync()` returned and could
overwrite a pending-write conflict on the same field. #514. A fire-and-forget flush raced the
destructive-transition guard. #585, fixed in #595.)

### SwiftData objects do not survive a reload

Every sync replaces the persisted Block by deleting it and inserting the re-parsed one. A `@Model`
object held across that point is detached, and its relationships come back nil about half the
time. Hold an address (week and day, or a `persistentModelID`) captured while the object is live,
and re-resolve it after the reload. `===` between models is sound only for two objects read in the
same pass; across a reload, compare by `persistentModelID`.

Look for a store or coordinator property typed as a `@Model` class that outlives `sync()`,
`session.week` read after a reload, or `===` against a model held from before one. (`reload()`
read the Week and Day off the Session it was still holding, so a background sync yanked a browsing
athlete to the Current Session 13 times in 25. #586. Now `WorkoutStore.browsedTo`, captured in
`view(_:)`.)

## Optionals

A defaulted parameter or an optional callback lets a caller omit a decision, and the compiler will
not say so. Require the parameter so every call site states its intent. Where a default is right,
it is the safe answer, never the convenient one. An optional Bool gets its nil case written out,
because `optional?.flag == false` reads nil as `false`.

Look for `= nil`, `= false`, or `= { _ in true }` on a parameter whose omission changes behaviour,
an optional closure a View could forget to pass, `?? Date()` and its relatives, or
`optional?.flag == false`. (A coordinator's former `isCurrentSessionScope` parameter defaulted to
`{ _ in true }`, so a coordinator wired without it answered "always at the live edge". #572. An
`optional?.flag == false` read a missing store as not busy. #582.) Now
`SheetsClient.fetchTabSnapshot(spreadsheetId:tabName:retrying:)` requires its backoff, and
`LastPerformedCard.onTap` is a `let` every caller must supply.

## Vocabulary

Names come from `CONTEXT.md`, including its avoid-lists. A synonym for an existing term is a
finding even when the code works.

Look for a new name for a concept the glossary already names, or one concept under several names
across files. (The Viewed Session shipped under five names, with its athlete-facing control named
after a different concept. #572, fixed in #591.)

## Tests

- **Coverage counts through the interface callers use.** Lower a CRAP score (`scripts/crap.sh
  gate`, ADR-0016) with a better design or a stronger test, never by weakening a pin, calling
  internals to paint lines green, or splitting a function into pieces with no name a reader would
  look for.
- **A pin that has to move is a behaviour change.** Argue it in the PR with the old and the new
  assertion, and never loosen it until green. (#598 moved one assertion and said why. #586 added
  its pins green on `main` before the refactor.)
- **Fake only the boundary** (the Sheets client, auth, and time). Fixtures under
  `Sources/WorkoutTracker/Fixtures/` stand in for Sheet data. A fake of the repo's own types is a
  finding.
- **Every fixture value is a literal or an offset from the fixture's reference date,** and a
  parsed date is pinned to the coach's cell text, never to an instant. (`SheetParser.parseDate`
  resolves in the machine's time zone, and a literal-instant pin passed in EDT and failed under
  `TZ=UTC`. #597, open.)
- **A wait for another task ends on the event, not on a count or a clock.** The fake resumes the
  test, or a bounded poll records a failure when it runs out, as `waitUntilHeld()` does. A fixed
  number of `Task.yield()` calls before an assertion is a flake, because the runtime promises no
  such ordering, a wall-clock budget is a flake under load, and an unbounded poll hangs CI instead
  of failing. (#548. The shapes are in `docs/TESTING.md`, Flaky Tests.)
- **A platform `#if` goes on the `@Test` declaration,** where the other platform drops the test,
  never inside the body, where the assertions compile away and the test passes empty. (#608. The
  lint catches a guard on the body's first line; judge the rest.)
- **A test that mirrors a one-line mapping adds no confidence** and breaks on any refactor. The
  gate does not need it: a function with cyclomatic complexity 1 scores 2 uncovered, under the
  target.

The shapes above that a regex can catch (the dropped task that writes a store field, the optional
Bool comparison, a wall-clock read in a fixture, the unbounded poll) are tracked as SwiftLint custom
rules in #637. Until they land, the review judges them.
