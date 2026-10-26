# Headless application boundary

Agents need to inspect and change application state without a simulator, and they must exercise
the code the iOS app runs, not a second implementation. Before this decision there was no
application object: `WorkoutTrackerApp.init` hand-wired four stores in two branches, every symbol
in the library was internal, and no Sheet existed without Google credentials.

`WorkoutApplication` is the one composition root. It owns the schema list and builds the model
container and the four stores from an `AppEnvironment` (in memory, on disk, or the device default;
which `SheetsClient`; where settings live; the clock). Both app launch branches and the CLI go
through it. Its public facade is the only surface outside the module, and every `public` instance
method of `WorkoutApplication` is a verb. Each verb calls the one store method the UI calls and
returns an `Encodable` value derived from the stores on each call. A gesture the UI makes in two
taps is two verbs, as Move On (`requestMoveOnCelebration`, `dismissMoveOnCelebration`) and Make
current (`view`, `makeCurrent`) are, so a caller can let the Sheet move between them, and a CLI
command makes both taps in one process. The stores, the models, and `SheetsClient` stay internal,
so the compiler enforces that a new CLI capability is a facade method over an existing store
method. A test compiled without `@testable` exercises exactly that surface.

A verb whose effect already holds converges: it writes nothing and returns the state, as Clear on
a Pending Set and Make current on the Current Session do. A verb whose effect cannot be reached
refuses with a domain error, as dismissing a Move On Celebration when none is open and making an
Unavailable Session current do. The UI offers neither tap: no overlay is open, and an Unavailable
tile does not open. A pin on an Unavailable Session would stand while the store fell back to
Sheet-derived progress, and no snapshot field would say so, so the facade refuses and the caller
learns why. Every verb that takes a Set address, `log` and `skip` among them, resolves it through
that availability check, so a Set in an Unavailable Session refuses with `session_unavailable` and
writes nothing. `log` and `skip` refused it before the check was shared, by the same predicate.

Fixtures are workbooks, not model graphs. `WorkbookScenario` produces a `LocalWorkbook` in the
coach's canonical layout, and the application reads it through the real parser and writes to it
through the real writer via `LocalWorkbookSheetsClient`. Over a home directory the client reads
`workbook.json` on every call and rewrites it after every write, so the file is the offline Sheet,
and an edit to it between two calls is a coach edit. A scenario must parse with no warnings.

The CLI is process-per-command over a home directory (`manifest.json`, `store.sqlite`,
`workbook.json`, `settings.json`). Every invocation opens the application fresh, so nothing
carries between commands except what is on disk, and the arc is reproducible from a clean home in
well under a second. `init` is the one command that touches storage without the facade: it writes
the manifest and the workbook before an application can exist. Settings live in
`home/settings.json` (#602), rewritten after every change, so deleting a home deletes them, `init`
resets them, and a moved or copied home keeps them. Tests and the in-memory environment keep
settings in memory and write no file.

The offline workbook, the scenarios, and the in-memory environment compile only under the
`OFFLINE_SHEET` condition, which `Package.swift` defines for the library and the Xcode project
defines for Debug builds (the hosted tests need it); release phone builds never ship fixture code.

**Considered alternatives:**
- *`@testable import` from the CLI:* reaches the stores directly and lets the CLI drift into a
  second implementation; a debug-only build would also break in release.
- *A daemon holding the application open:* faster per call but adds cross-invocation state and a
  lifecycle; the per-command cost is already milliseconds.
- *Seeding SwiftData graphs directly (as the UI-test fixture does):* bypasses the parser and
  writer, so it cannot prove the Sheet round trip.
- *A `UserDefaults` suite per home, named by a hash of the home path:* the first slice shipped it.
  Every suite persists as a plist under `~/Library/Preferences` that nothing deletes, and a moved
  home lost its settings. Settings now live in `home/settings.json` (#602).

<!-- doc-symbols: not-in-tree workbook.json manifest.json home/settings.json -->
