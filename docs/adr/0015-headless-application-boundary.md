# Headless application boundary

Agents need to inspect and change application state without a simulator, and they must exercise
the code the iOS app runs, not a second implementation. Before this decision there was no
application object: `WorkoutTrackerApp.init` hand-wired four stores in two branches, every symbol
in the library was internal, and no Sheet existed without Google credentials.

`WorkoutApplication` is the one composition root. It owns the schema list and builds the model
container and the four stores from an `AppEnvironment` (in memory, on disk, or the device default;
which `SheetsClient`; where settings live; the clock). Both app launch branches and the CLI go
through it. Its public facade is the only surface outside the module: `selectSpreadsheet`,
`snapshot`, `session`, `log`, `flush`, `sync`, `sheet`. Each verb calls the store method the UI
calls and returns an `Encodable` value derived from the stores on each call. The stores, the
models, and `SheetsClient` stay internal, so the compiler enforces that a new CLI capability is a
facade method over an existing store method. A test compiled without `@testable` exercises exactly
that surface.

Fixtures are workbooks, not model graphs. `WorkbookScenario` produces a `LocalWorkbook` in the
coach's canonical layout, and the application reads it through the real parser and writes to it
through the real writer via `LocalWorkbookSheetsClient`, which persists to `workbook.json`. A
scenario must parse with no warnings.

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
