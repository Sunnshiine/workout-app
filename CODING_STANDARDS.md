# Coding standards

Each bullet names a defect this repo shipped. Apply every one to every hunk, cite the bullet, and
quote the hunk. Flag only what a lint cannot judge; `.swift-format` and the two `.swiftlint.yml`
files own formatting and the mechanical rules. Read a trailing issue or symbol when a bullet does
not settle a hunk.

## Architecture

- **A write that reaches the Sheet or the cache outside `SyncCoordinator` and its pending-write
  queue,** or a transition that could abandon queued Set Logs without asking
  `canBeginDestructiveTransition`. (ADR-0001, ADR-0006, #585, fixed in #595.)
- **Logic in a View that needs a test,** such as a computed property ORing store state, a `switch`
  on domain state in `body`, or a decision the `workout` CLI cannot see. `swift test` never reaches
  `App/Views/` (ADR-0017), so it lives in the library. (#582, `DestructiveTransition`.)
- **A type that only forwards.** If deleting it loses nothing, the concept it fronts is what needs
  a module. (#514, #570, #572, `SyncOutcome`. The `codebase-design` skill carries the long form.)

## State

- **A derived fact with more than one owner.** A latch every mutating method must set, a mirror
  re-derived with drifting conditions, or a predicate spelled twice. (#586, #570, #572.)
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
  `false`, so write the nil case out. (#572, #582, `SheetsClient.fetchTabSnapshot`.)

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
  resolves in the machine's time zone. (#597.)
- **A wait that ends on a count or a clock.** Counted `Task.yield()`, a wall-clock budget, and an
  unbounded poll are the three flake shapes. The fake resumes the test, or a bounded poll records a
  failure when it runs out, as `waitUntilHeld()` does. (#548, `docs/TESTING.md`.)
- **A platform `#if` inside a `@Test` body,** where the assertions compile away and the test passes
  empty. It goes on the declaration. (#608. The lint catches the body's first line. Judge the rest.)
- **A test that mirrors a one-line mapping.** It breaks on any refactor and the gate does not need
  it. A complexity-1 function scores 2 uncovered, under the target.
