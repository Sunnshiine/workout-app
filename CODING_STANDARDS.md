# Coding standards

Each bullet names a defect this repo shipped that takes context a regex does not have. `CONTEXT.md`,
`docs/adr/`, `PRODUCT.md`, and `DESIGN.md` win over anything here.

Apply every rule to every hunk, cite the bullet, and quote the hunk. Flag only what a lint does not
already judge, and never a preference. A force unwrap, force try, force cast, or a font built
outside the Theme seam in the app is a lint error, not a finding; `Tests/.swiftlint.yml` lists
what a test body may do. Read a trailing issue or symbol when a bullet does not settle a hunk.

## Architecture

- **A write that reaches the Sheet or the cache outside `SyncCoordinator` and its pending-write
  queue,** or a transition that could abandon queued Set Logs without asking
  `canBeginDestructiveTransition`. (ADR-0001, ADR-0006, #585, fixed in #595.)
- **Logic in a View that needs a test,** such as a computed property ORing store state, a `switch`
  on domain state in `body`, or a decision the `workout` CLI cannot see. `swift test` never reaches
  `App/Views/` (ADR-0017), so it lives in the library. (#582, `DestructiveTransition`.)
- **A type that only forwards,** a method added where a caller could have asked a deeper question,
  or a question already answered privately in a second place. If deleting the type loses nothing,
  the concept it fronts is what needs a module. (#514, #570, #572, `SyncOutcome`. The
  `codebase-design` skill carries the long form.)

## State

- **A derived fact with more than one owner.** A latch every mutating method must set, a mirror
  re-derived with drifting conditions, or a predicate spelled twice. (#586, #570 fixed in #574,
  #572 fixed in #591, `LiveEdge.isAtLiveEdge`.)
- **A control signal that does not read what it claims to measure,** such as `state == .someCase`
  as a guard, or a Bool true only because the last writer set it. (`isSyncing` read the banner's
  display enum. #585, now `SyncCoordinator.isSyncing`.)
- **An outcome that is not an enum with one case per outcome,** such as a `[String]` payload with
  two producers, `messages.first ?? "…"`, English composed in a store, or a method that sets
  `state` as it exits. (#589, #514, #598, `SyncOutcome.sync(sheetRead:flush:)`.)

## Concurrency

- **A dropped or detached `Task` that assigns a store field after its owning method returned.**
  Hold and await work the sequence needs. (#514, #585, fixed in #595.)
- **A `@Model` object held across a reload.** Hold an address (week and day, or a
  `persistentModelID`) and re-resolve. `===` is sound only within one read pass. (#586,
  `WorkoutStore.browsedTo`.)

## Optionals

- **A defaulted parameter or optional callback that lets a caller omit a decision,** such as
  `= nil`, `= false`, `= { _ in true }`, or `?? Date()` where omission changes behaviour. A right
  default is the safe answer, not the convenient one. `optional?.flag == false` reads nil as
  `false`, so write the nil case out. (#572, #582,
  `SheetsClient.fetchTabSnapshot(spreadsheetId:tabName:retrying:)`.)

## Vocabulary

- **A name `CONTEXT.md` does not use,** or one concept under several names. Its avoid-lists bind
  too, and a synonym is a finding even when the code works. (#572, fixed in #591.)

## Tests

- **A CRAP score lowered by weakening a pin, calling internals, or splitting a function into pieces
  no reader would look for.** Lower it by design or a stronger test (`scripts/crap.sh gate`,
  ADR-0016). A pin that has to move is a behaviour change, argued in the PR. (#598.)
- **A fake of anything but the boundary,** which is the Sheets client, auth, and time. Fixtures
  under `Sources/WorkoutTracker/Fixtures/` stand in for Sheet data.
- **A fixture value that is not a literal or an offset from the fixture's reference date,** or a
  parsed date pinned to an instant rather than the coach's cell text. `SheetParser.parseDate`
  resolves in the machine's time zone. (#597, fixed in #684.)
- **A wait that ends on a count or a clock.** Counted `Task.yield()`, a wall-clock budget, and an
  unbounded poll are the three flake shapes. The fake resumes the test, or a bounded poll records a
  failure when it runs out, as `HeldCall` in `Tests/Support/` does. A continuation ignores the time
  limit's cancellation, so `HeldCall` parks one call at a time and none after its poll gave up. Any
  other call returns at once, and the test fails instead of hanging. The poll, the state it reads,
  and the work that sets it share one actor, so each yield gives that work a turn. A poll on
  another actor can exhaust its count before a loaded main actor runs the work. (#548,
  `docs/TESTING.md`, `ControlledValidationClient` in #637, #707.)
- **A platform `#if` inside a `@Test` body,** where the assertions compile away and the test passes
  empty. It goes on the declaration. (#608. The lint catches a guard below comment lines and
  single-line `let` or `var` bindings. It misses one below a binding that holds a closure, a binding
  that spans lines, or any other statement, so judge those.)
- **A test that mirrors a one-line mapping.** It breaks on any refactor and the gate does not need
  it. A complexity-1 function scores 2 uncovered, under the target.

Four shapes a regex can catch are SwiftLint errors in `.swiftlint.yml` (#637). The review still
judges what each regex misses. A hit is fixed in the code, or exempted on its line with a reason:

- `unstructured_task_is_held` skips `App/Views/`, where `Button { Task { … } }` is the idiom, so the
  review judges a View method that starts a Task writing a store field. The rule reads only a line
  that starts with `Task`, so `_ = Task { }`, `let _ = Task { }`, `Task<Void, Never> { }`,
  `Task(operation: { })`, a `Task {` in the middle of a line, and `Task(priority: f()) {` pass it.
  It flags a Task held on the line after `x =` and a Task a function returns implicitly, though
  both are held.
- `optional_bool_needs_a_nil_answer` catches `x?.flag`, `(try? …)`, `x.map(…)`, and `x.map { … }`
  compared to a Bool literal on one line. A reversed comparison (`true == x?.flag`), a chain past
  a call (`x?.f().flag`), a nested call inside the chain (`x?.f(g(a))`), a subscript
  (`x?[i].flag`), a map whose closure or argument spans lines, and a plain `Bool?` value compared
  to a literal pass it. It flags a non-optional call chained after the map
  (`.map(abs).contains(1) == true`, `.map { … }.allSatisfy { … } == true`) and a comparison inside
  a string literal. It skips `Tests/`, where `#expect(x?.flag == true)` failing on nil is the
  assertion doing its job.
- `fixture_dates_are_literal` catches `Date()`, `Date.now`, `Date(timeIntervalSinceNow:)`, and the
  current `TimeZone` and `Calendar`. The `.now` shorthand, a `DateFormatter` or a
  `Calendar(identifier:)` left on the machine time zone (#597), `Locale.current`, and a
  `ContinuousClock.now` deadline pass it. It skips `Tests/UI/`, whose polling helpers keep
  wall-clock deadlines.
- `polling_loops_are_bounded` catches a `while`, `repeat`, or `for _ in` loop whose whole body is
  `await Task.yield()`. A loop whose condition holds a closure, whose body does anything else, or
  whose index is named (`for i in 0..<n`) passes it.

`unstructured_task_is_held` and `optional_bool_needs_a_nil_answer` also reach `WorkoutShared/` and
`WorkoutWidgets/`. The font and microlabel rules stop at the app, and no bullet here judges type
or case in the widget. The widget target does not compile `Sources/WorkoutTracker/`, so the Theme
seam the font rule points to is not there. `scripts/tests/swiftlint-custom-rules.test.sh` pins
every shape named here.
