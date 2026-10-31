# Coding standards

Each bullet names a defect this repo shipped that takes context a regex does not have. `CONTEXT.md`,
`docs/adr/`, `PRODUCT.md`, and `DESIGN.md` win over anything here.

Apply every rule to every hunk, cite the bullet, and quote the hunk. Flag only what a lint does not
already judge, and never a preference. A force unwrap, force try, force cast, or a font built
outside the Theme seam in the app is a lint error, not a finding; `Tests/.swiftlint.yml` lists
what a test body may do. Read a trailing issue or symbol when a bullet does not settle a hunk.

Each bullet ends with what enforces it: a SwiftLint rule, a script, a test, or judgment, which is
the review's. `scripts/rule-table.sh` fails a bullet that names none, and writes the table in
`AGENTS.md` from these lines.

A claim about runtime behaviour, such as SwiftUI layering or transaction order, gesture or focus
callback order, or timing, is a hypothesis. The finding names the measurement that would settle
it, and the owner runs that measurement before changing code. (#860: a `.zIndex` two reviewers
called redundant was the lift, and deleting it cut the Superset bud.)

## Architecture

- **A write that reaches the Sheet or the cache outside `SyncCoordinator` and its pending-write
  queue,** or a transition that could abandon queued Set Logs without asking
  `canBeginDestructiveTransition`. (ADR-0001, ADR-0006, #585, fixed in #595.) Enforced by:
  judgment.
- **A Sheet write addressed by a weaker identity than the parser read,** such as an Exercise's
  name where the Session holds two of that name. Only the parser mints an `ExerciseReference`, and
  every write target comes from `SetCoordinates(of:)`. (#102, #813, #962, #963, #1049.) Enforced
  by: `exercise_references_are_parsed`, `Tests/Unit/SheetRoundTripTests.swift`, judgment.
- **Logic in a View that needs a test,** such as a computed property ORing store state, a `switch`
  on domain state in `body`, or a decision the `workout` CLI cannot see. `swift test` never reaches
  `App/Views/` (ADR-0017), so it lives in the library. (#582,
  `SheetConnection.canBeginDestructiveTransition`.) Enforced by: judgment.
- **A type that only forwards,** a method added where a caller could have asked a deeper question,
  or a question already answered privately in a second place. If deleting the type loses nothing,
  the concept it fronts is what needs a module. (#514, #570, #572, `SyncOutcome`. The
  `codebase-design` skill carries the long form.) Enforced by: judgment.

## State

- **A derived fact with more than one owner.** A latch every mutating method must set, a mirror
  re-derived with drifting conditions, or a predicate spelled twice. (#586, #570 fixed in #574,
  #572 fixed in #591, `LiveEdge.isAtLiveEdge`.) Enforced by: `DifferentialStateTests`, judgment.
- **A control signal that does not read what it claims to measure,** such as comparing the display
  `state` to one case as a guard, or a Bool true only because the last writer set it. (`isSyncing`
  read the banner's display enum. #585, now `SyncCoordinator.isSyncing`.) Enforced by: judgment.
- **An outcome that is not an enum with one case per outcome,** such as a `[String]` payload with
  two producers, `messages.first ?? "…"`, English composed in a store, or a method that sets
  `state` as it exits. (#589, #514, #598, `SyncOutcome.sync(sheetRead:flush:)`.) Enforced by:
  judgment.

## Concurrency

- **A dropped or detached `Task` that assigns a store field after its owning method returned.**
  Hold and await work the sequence needs. The rule skips `App/Views/`, where
  `Button { Task { … } }` is the idiom, so the review judges a View method that starts a Task
  writing a store field. (#514, #585, fixed in #595.) Enforced by: `unstructured_task_is_held`,
  judgment.
- **A `@Model` object held across a reload.** Hold a `SessionAddress`, a `SessionCoordinate`, a
  `SetCoordinates.ID`, or a `persistentModelID`, and re-resolve it from the store's Block. `===` is
  sound only within one read pass. The rule reads only the four-space indent of a type's own
  members, because deeper in, a nested type's property and a method's local `var` look alike, so a
  struct that wraps a model and a property of a type nested in a function pass it. (#586, #976,
  #1052, #972, #1036, #1053, `WorkoutStore.viewing`, `SessionCoordinator.sessionCoordinate`.)
  Enforced by: `model_held_across_reload`, judgment.

## Optionals

- **A defaulted parameter or optional callback that lets a caller omit a decision,** such as
  `= nil`, `= false`, `= { _ in true }`, or `?? Date()` where omission changes behaviour. A right
  default is the safe answer, not the convenient one. A new default under `Sources/` or `App/`
  carries `// default: <reason>` on its line, and the lint's failure names the baseline rewrite for
  a rename. Review still judges each reason, the baselined defaults, and `?? Date()`.
  `optional?.flag == false` reads nil as `false`, so write the nil case out. The Optional Bool rule
  skips `Tests/`, where `#expect(x?.flag == true)` failing on nil is the assertion doing its job. (#572,
  #582, #813, `SheetsClient.fetchTabSnapshot(spreadsheetId:tabName:retrying:)`.) Enforced by:
  `scripts/lint-defaults.py`, `optional_bool_needs_a_nil_answer`, judgment.

## Vocabulary

- **A name `CONTEXT.md` does not use,** or one concept under several names. Its avoid-lists, and
  those of the area files it links (`docs/context/logging.md`), bind too, and a synonym is a
  finding even when the code works. (#572, fixed in #591.) Enforced by:
  `scripts/lint-vocabulary.py`, judgment.

## Docs

- **A doc that still describes what the diff removed, renamed, split, or changed,** in `AGENTS.md`,
  `docs/`, a skill, a README, or a script's `--help`. Grep the docs for the concept's words, not
  only its symbol, and read each hit against the new behaviour. A file split in parts leaves a
  pointer that names one part, and `scripts/doc-drift.py` lists the doc lines that name a file the
  branch split or moved. (#1025 shipped the verify skill naming one of four
  `host-admission*.test.sh` files. Late review caught the same miss in #909, whose `AGENTS.md` still
  described the load gate, and in #1019, whose avoid-list rule still named `CONTEXT.md` alone.)
  Enforced by: `scripts/lint-doc-symbols.py`, `scripts/doc-drift.py`, judgment.

## Comments

- **A comment that narrates the next line,** or restates a name, a type, or a test. Delete it.
  Enforced by: judgment.
- **A deleted comment that carried what the code cannot show:** a platform fact no test pins, a
  measured number with its evidence, or a contract every conformer honours. It stays. A reviewer
  who wants one gone names the test that would pin it instead. (#860 lost the bud wake's timing
  reason twice, and #861 lost the `SheetSwitchSyncing` contract a reviewer had asked for.)
  Enforced by: judgment.

## Tests

- **A CRAP score lowered by weakening a pin, calling internals, or splitting a function into pieces
  no reader would look for.** Lower it by design or a stronger test (ADR-0016). A pin that has to
  move is a behaviour change, argued in the PR. (#598.) Enforced by: `scripts/crap.sh`, judgment.
- **A fake of anything but the boundary,** which is the Sheets client, auth, and time. Fixtures
  under `Sources/WorkoutTracker/Fixtures/` stand in for Sheet data. Enforced by: judgment.
- **A fixture value that is not a literal or an offset from the fixture's reference date,** or a
  parsed date pinned to an instant rather than the coach's cell text. `SheetParser.parseDate`
  resolves in the machine's time zone. (#597, fixed in #684.) Enforced by:
  `fixture_dates_are_literal`, judgment.
- **A wait that ends on a count or a clock.** Counted `Task.yield()`, a wall-clock budget, and an
  unbounded poll are the three flake shapes. A fake never parks the test on a bare continuation,
  because a continuation ignores cancellation and a missed release hangs the run instead of failing
  it (#746). Every wait on work the test does not control goes through `waitUntil` or
  `HeldCall.waitUntilHeld` in `Tests/Support/`, which record a failure when the bound runs out. The
  poll, the state it reads, and the work that sets it share one actor, so each yield gives that
  work a turn. A poll on another actor can exhaust its count before a loaded main actor runs the
  work. A bare `ContinuousClock.now` held as a start instant passes the clock rule. A continuation
  that only a release the test must remember resumes is a park. One that resumes at once, or that
  a cancel handler or a failed wait also resumes, is exempt on its line with that reason. A park
  with neither is exempt only when its line cites the issue that tracks the missing release, open
  or closed as `wontfix`. (#548, #543, #899, #1014, #936, `docs/TESTING.md`,
  `ControlledValidationClient` in #637, #707.) Enforced by: `tests_wait_on_events_not_clocks`,
  `tests_never_park_on_a_bare_continuation`, `polling_loops_are_bounded`,
  `scripts/flake-guard.sh`, judgment.
- **A platform `#if` inside a `@Test` body,** where the assertions compile away and the test passes
  empty. It goes on the declaration. (#608.) Enforced by: `platform_guard_on_test_declaration`,
  judgment.
- **A test that mirrors a one-line mapping.** It breaks on any refactor and the gate does not need
  it. A complexity-1 function scores 2 uncovered, under the target. Enforced by: judgment.
- **A test that passes whatever the code under test does.** It compares a value with itself or
  with the same call made twice, takes its expected value from the code under test, asserts a
  stub's own state, fetches what it inserted from the same SwiftData context, writes only the
  values a model falls back to, or exercises only what the compiler synthesizes. Break the logic or
  the wiring with `scripts/mutate.sh`: cross two cases, read the wrong token, keep a field out of
  the store. If no mutant turns the test red, delete it, or assert a literal that a plausible bug
  would change. Editing a constant's own literal always fails its pin, so judge a test that
  restates a constant or a copy string another way. It is tautological when another gate already
  pins the value, as the Visual baselines pin the palette, surfaces, and radii, or when nothing
  reads it. A token DESIGN.md specifies that no other gate sees, such as a motion duration, a haptic
  tuning, or a tabular-figures flag, is that spec's one pin and stays. (#807, #808, #809.) Enforced
  by: `scripts/mutate.sh`, `scripts/mutate-advisory.sh`, judgment.

## What each SwiftLint rule misses

Shapes a regex can catch are SwiftLint errors in `.swiftlint.yml` (#637). Each rule's cases are the
functions of its fixture under `scripts/tests/swiftlint-custom-rules/`, and
`scripts/tests/swiftlint-custom-rules.test.sh` pins every one. A name ending `IsFlagged` is a hit,
and one ending `Passes` is clean. One ending `IsMissed` is a shape the rule cannot see, so the
review judges it. One ending `IsFalselyFlagged` is a false hit. A hit is fixed in the code, or
exempted on its line with a reason, and `scripts/lint-exemptions.py` fails the exemption of a rule
that stops a bug when it cites no open or `wontfix` issue. The font and microlabel rules stop at
the app, because the widget target does not compile the Theme seam, and no bullet here judges type
or case in the widget.
