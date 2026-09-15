# CRAP as the change-risk gate

Nothing measured how risky a function was to change. SwiftLint warned on cyclomatic complexity
alone, coverage was never collected, and the two were never joined. A pure lookup table and an
untested state machine looked the same to every tool the repo ran.

Every production function gets a CRAP score, `cc^2 * (1 - coverage)^3 + cc`, where `cc` is
cyclomatic complexity and `coverage` is the fraction of the function's instrumented lines that
`swift test` executed. The target is 6 or lower per function. A fully covered function passes with
up to 6 branches; an uncovered one passes only with 2. The score is not an average: a single
function above 6 fails the gate.

`tools/crap` is a separate SwiftPM package that counts complexity with swift-syntax (Apple's
parser, so function boundaries and closures are exact) and joins it with llvm-cov line records
from the coverage profile `swift test --enable-code-coverage` writes. The counting rules are in
`tools/crap/README.md` and each rule has a test. `scripts/crap.sh` is the one command: it runs
the tests with coverage, exports lcov, builds the scorer, and prints the worst rows or evaluates
the gate. `tools/crap/baseline.tsv` lists the functions still above 6 with their recorded score.
The gate fails on a new function above 6, on a baselined function that got worse, and on a
baseline row that no longer applies, so the baseline can only shrink.

The measured scope is what `swift test` compiles: the `WorkoutTracker` library target and
`WorkoutCLI`. `Views/`, `LiveActivity/`, `Sheets/GoogleAuth.swift`, `WorkoutTrackerApp.swift`,
`WorkoutShared/`, and `WorkoutWidgets/` are unmeasured, about a third of production Swift. Code
that compiles only on iOS (`#if canImport(UIKit)`) is listed as unmeasured, not scored as
uncovered. Meeting the target means meeting it across the measured scope; the unmeasured scope
is a known gap, not a pass.

**Considered alternatives:**
- *lizard:* its Swift reader merged three declarations into one function at the first hotspot
  checked and does not count `??`, so per-function scores would be wrong where they matter most.
- *SwiftLint's `cyclomatic_complexity` rule:* reports only violations above a threshold, does not
  count `&&`, `||`, `??`, or ternaries, and has no coverage input.
- *Coverage from the simulator:* would measure the Views, but every run costs minutes and a booted
  simulator; the headless run costs about 20 seconds and runs in the PR gate. A simulator run can be
  added later as a second, reporting-only input to the same scorer.
- *Excluding lookup tables from the count:* every switch case is a branch under every standard
  definition; changing the rule to fit the code would make the number untrustworthy. Tables that are
  data are written as data instead.
