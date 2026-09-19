# One project definition and source layout

Three files described the build. `Package.swift` fed `swift test` and the CLI. The committed
`WorkoutTracker.xcodeproj` fed local builds, the simulator suites, the CI visual tests, agents, and
XcodeBuildMCP. `project.yml` fed only the two TestFlight workflows, which ran an unpinned XcodeGen
before every archive. XcodeGen also rewrites `WorkoutTracker/Info.plist` from `project.yml`, so
when #505 added `UIAppFonts` to the committed plist and not to `project.yml`, every TestFlight build
shipped the bundled fonts without registering them and fell back to the system font (#603).
Nothing but the release ran the generated project, so nothing caught the drift.

The committed Xcode project is the only project definition. The release workflows archive it as
committed, and `WorkoutTracker/Info.plist` holds the marketing version. The dev-flavor hooks
(`BUNDLE_ID_SUFFIX`, `APP_DISPLAY_NAME`, `APPICON_NAME`) are project-level build settings that the
PR workflow overrides on the command line. No generator produces or checks the project.

Three layout changes follow as separate changes, and this record fixes their design.

Adding a file will not require a project edit. More than two thirds of the 79 commits that touched
the pbxproj only registered files. The test targets already use Xcode buildable (synchronized)
folders. The app, widget, and shared source groups will become buildable folders too, so a file
placed in one belongs to its target.

A directory boundary will replace the `Package.swift` exclude list. Code that SwiftPM and the app
both compile moves to `Sources/WorkoutTracker/`, the CLI to `Sources/WorkoutCLI/`, and iOS-only
code (the entry point, Views, LiveActivity, GoogleAuth, the assets, and `Info.plist`) to `App/`.
SwiftPM will then compile only `Sources/`, so a new iOS-only file goes under `App/` and needs no
manifest edit to stay out of `swift test`.

The code stays one module. The CLI still sees only the public facade from ADR-0015, and Views keep
internal access to the stores and models.

Reopen the one-module decision when a second iOS target, such as a watch app, needs the domain code.

**Considered alternatives:**
- *XcodeGen as the source, with the pbxproj gitignored:* every worktree, agent, and XcodeBuildMCP
  call would have to regenerate before it could build. The Xcode 27.2 beta already refuses to open
  some projects that XcodeGen generates without a warning (XcodeGen issue #1651).
- *Tuist:* a new toolchain for a one-developer app.
- *A thin app shell with all code in a local package:* Views would need `package` access on
  everything they touch. SwiftPM gives every target in one package the same package name, so the
  CLI could see those symbols and the compiler would no longer enforce the ADR-0015 facade.
- *A layered multi-module split:* a trial of only the first cut, Models plus Parsing in their own
  target, needed about 250 `package` modifiers. One dependency cycle runs through seven folders,
  and no build-time problem has been measured.
