# Coding standards

The review standard for this repo. `CONTEXT.md` (vocabulary), `docs/adr/` (decisions), `PRODUCT.md`
and `DESIGN.md` (product and UI work) win over anything here. Formatting and every mechanical rule
are settled by `.swift-format` and `.swiftlint.yml`, including its custom rules; a reviewer flags
only what a lint does not already judge, and never a preference. A rule earns a line here when it
cost this repo a shipped bug and applying it takes context a regex does not have. Delete a rule
that stops paying.

Apply every rule to every hunk of the diff. For each finding, cite the rule's heading and quote the
hunk.

## Vocabulary

Names come from `CONTEXT.md`, including its avoid-lists. A synonym for an existing term is a finding
even when the code works.

Look for a new name for a concept the glossary already names, or one concept under several names
across files.

It shipped as the Viewed Session named five ways (`displayedSession`, "live edge",
"Displayed Session", `previewSession`, `isCurrentSessionScope`), with its athlete-facing control
named after a different concept, the persisted Current Session override (#572, fixed in #591).

## The Sheet is the truth

The Google Sheet is the single source of truth and the app is a read-write client with a local cache
(ADR-0001). Local state that diverges from Sheet-derived truth, or overwrites it, without going
through `Stores/` and the sync path is a correctness bug, not a style issue.

Look for a write to the Sheet or the cache that bypasses `SyncCoordinator` and the pending-write
queue (ADR-0006), or a transition that discards queued Set Logs without the destructive-transition
guard.

It shipped as `canBeginDestructiveTransition` answering `true` during a live sync, so switching
Sheets could abandon Set Logs the athlete had recorded (#585, fixed in #595).

## One owner per fact

A fact derived from other state has exactly one place that answers it. Three shapes break this.

- A latch. A Bool that every method changing the state must remember to set.
  `shouldPreserveDisplayedSessionOnReload` was assigned at ten sites, seven of them `false`, and a
  new navigation method could forget it silently (#586).
- A mirror. A value re-derived in several places with drifting conditions. Last Set RPE was
  re-decided in five places and the skip path forgot it, leaving a stale RPE in the coach's Sheet
  (#570, fixed in #574).
- A predicate spelled twice. "Is the athlete at the live edge" was decided three times, once by
  object identity and twice by model identity (#572, fixed in #591).

Look for the same condition in two files, a Bool assigned in more than two methods, or a comment
that explains when a combination of fields is valid.

The fix looked like `WorkoutStore.view(_:)`, the only writer of `viewedSession`, answering the
reload rule once (`WorkoutTracker/Stores/WorkoutStore.swift:187-194`), and one
`LiveEdge.isAtLiveEdge` (`WorkoutTracker/Progress/LiveEdge.swift:19`).

## Control signals come from what they claim

A value that gates behaviour reads the thing it claims to measure. Display state is not a control
signal, and a background task never writes a foreground field.

Look for `state == .someCase` used as a guard, a Bool that is `true` only because the last writer
happened to set it, or a detached or dropped task assigning a store property.

It shipped as `isSyncing` reading the banner's display enum, which `flushPending` reset to `.idle`
mid-sync, so the destructive-transition guard opened with a sync on the wire (#585). The history
backfill ran detached after `sync()` returned and could overwrite a pending-write conflict on the
same field (#514).

The fix looked like `isSyncing` reading two in-flight counters that only their owners change
(`WorkoutTracker/Stores/SyncCoordinator.swift:202`), with the banner derived from them. The review
catches the dropped-task shape today and judges what a held task is allowed to write. #637 adds an
`unstructured_task_is_held` lint for the shape.

## Outcomes are enums with one case per outcome

A result type has one case per thing that can happen, carries what the step produced, and leaves the
wording to the presentation layer. Precedence between outcomes lives in one function, and a step
returns its result instead of assigning state as a side effect.

Look for a case whose payload is `[String]` fed by more than one producer, `messages.first ?? "…"`,
English composed inside a store or coordinator, or a method that sets `state` on its way out.

It shipped as `.conflict([String])` carrying five outcomes, from "your Set Log did not save" to
"the parser has a note", rendered identically (#589, #514).

The fix looked like `SyncOutcome` (`WorkoutTracker/Stores/SyncOutcome.swift:9-25`), precedence in
`SyncOutcome.sync(sheetRead:flush:)`, and the queued count returned on
`PendingWriteFlushResult.stoppedForRetry(queued:)` instead of assigned (#598).

## Optionals

A defaulted parameter or an optional callback lets a caller omit a decision, and the compiler will
not say so. Prefer a required parameter so every call site states its intent. Where a default is
right, it is the safe answer, never the convenient one.

Look for `= nil`, `= false`, or `= { _ in true }` on a parameter whose omission changes behaviour,
an optional closure a View could forget to pass, or `?? Date()` and its relatives turning a missing
value into a plausible one.

It shipped as a coordinator's `isCurrentSessionScope` defaulting to `{ _ in true }`, so a
coordinator wired without it silently answered "always at the live edge" (#572).

The fix looked like `SheetsClient.fetchTabSnapshot(spreadsheetId:tabName:retrying:)` requiring
its backoff (`WorkoutTracker/Sheets/SheetsClient.swift:26-35`) and `LastPerformedCard.onTap`
declared `let`, so every caller says whether the line is tappable
(`WorkoutTracker/Views/LastPerformedCard.swift:5-9`).

The review catches `optional?.flag == false` and its spellings today, and judges every other
default. #637 adds an `optional_bool_needs_a_nil_answer` lint for the comparison.

## SwiftData objects do not survive a reload

Every sync replaces the persisted Block by deleting it and inserting the re-parsed one. A `@Model`
object held across that point is detached, and its relationships come back nil about half the time.
Hold an address (week and day, or a `persistentModelID`) captured while the object is live, and
re-resolve it after the reload. Compare models by `persistentModelID`, never with `===`.

Look for a store or coordinator property typed as a `@Model` class that outlives `sync()`,
`session.week` read after a reload, or `===` between models.

It shipped as `reload()` reading the Week and Day off the Session it was still holding, so a
background sync yanked a browsing athlete to the Current Session 13 times in 25 (#586).

The fix looked like `browsedTo: (week: Int, day: Int)?` captured in `view(_:)`
(`WorkoutTracker/Stores/WorkoutStore.swift:24-31`).

## Views hold no logic that needs a test

`WorkoutTracker/Views/` is outside the SPM library target (`Package.swift:17-26`), so `swift test`
cannot reach it. A guard, a calculation, or a branch that decides behaviour lives in `Stores/`,
`Progress/`, `Models/`, `Parsing/`, or `LoadSuggestionEngine.swift`, and the View reads the answer.
CI still compiles Views, so "cannot be verified here" is not a reason to leave one alone.

Look for a computed property on a View that ORs store state together, a `switch` on domain state
inside `body`, or a decision the `workout` CLI would need and cannot see.

It shipped as the wider half of the destructive-transition guard living in `SettingsView`
computed properties where no unit test could reach it (#582).

## Deep modules

Prefer a small interface over a deep implementation. The deletion test from #514 decides it: if
deleting a type would lose nothing (a thin switch over prose, a pass-through), the interface is
shallow and the concept it fronts is what needs a module. Three PRDs applied the test, the sync
outcome (#514), Last Set RPE (#570), and the Viewed Session (#572). The `codebase-design` skill
carries the long form.

Look for a new type that only forwards, a method added to an interface where a caller could have
asked a deeper question, or a "which Set is final" question answered privately in a second place.

## Tests

- Coverage counts through the interface callers use. Lower a CRAP score (`scripts/crap.sh gate`,
  ADR-0016) with a better design or a stronger test, never by weakening a pin, calling internals
  to paint lines green, or splitting a function into pieces with no name a reader would look for.
- A pin that has to move is a behaviour change. Argue it in the PR with the old and the new
  assertion; never loosen it until green. #598 moved one assertion and said why; #586 added its
  pins green on `main` before the refactor.
- Fake only at the boundary: the Sheets client, auth, time. Fixtures under
  `WorkoutTracker/Fixtures/` stand in for Sheet data. A fake of the repo's own types is a finding.
- Every fixture value is a literal or an offset from the fixture's reference date, and a parsed
  date is pinned to the coach's cell text, never to an instant. `SheetParser.parseDate` resolves in
  the machine's time zone, and a literal-instant pin passed in EDT and failed under `TZ=UTC`
  (#597). The review catches wall-clock reads and the time-zone assumption. #637 adds a
  `fixture_dates_are_literal` lint for the reads.
- A test that mirrors a one-line mapping adds no confidence and breaks on any refactor. The gate
  does not need it: a function with cyclomatic complexity 1 scores 2 uncovered, under the target.
- Flake discipline (a fake resumes the test, no wall-clock budgets) is `docs/TESTING.md`, Flaky
  Tests. The `platform_guard_on_test_declaration` lint catches the `@Test` whose body opens with a
  platform `#if` (#608, landed in #632), and #637 adds a `polling_loops_are_bounded` lint for the
  unbounded yield loop.
