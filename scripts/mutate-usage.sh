# shellcheck shell=bash
usage() {
    cat <<'EOF'
scripts/mutate.sh proves a test pins a line. A mutant is one change to the code, and some test must
fail on it. Mutants build in a scratch tree, never in your worktree; uncommitted files are included.

Examples:
  scripts/mutate.sh --diff origin/main                 mutants on the lines your branch changed
  scripts/mutate.sh --filter RPETableTests Sources/WorkoutTracker/RPETable.swift '6s/6...10/7...10/'
                                                       one hand-written mutant: a sed command on line 6
  scripts/mutate.sh --sim "$(scripts/ensure-simulator.sh 'iPhone 17 Pro' 27.0)" --diff origin/main App
                                                       App/ is compiled only by the simulator suite

Each mutant prints a row  OUTCOME  FILE:LINE  OP  CHANGE  FIRST-KILLER:
  killed       good: a test failed, crashed, or timed out. results.tsv lists every killer.
  SURVIVED     bad: no test failed and an #error on the line breaks the build. Add or sharpen a test.
  flaky        every killer also failed on the untouched snapshot; fix the flake first.
  nocompile    the compiler rejects the mutant (no verdict).
  unreachable  this build never compiles the line: needs --sim, or the #if arm the other run covers.
  error        the runner failed without naming a test, or the build failed elsewhere.
  not run      --max left it out.
Exit 0 when every mutant was killed (a generated nocompile does not count). Exit 1 on flaky, SURVIVED,
unreachable, error, not run, a hand-written nocompile, or none killed. Exit 2 on bad usage or a failing
baseline. Exit 75 when every scratch tree or the simulator is busy: rerun.

Usage: scripts/mutate.sh [--sim UDID] [--filter SEL]... FILE SED_EXPR [SED_EXPR...]
       scripts/mutate.sh [--sim UDID] [--filter SEL]... [--max N] --diff BASE [PATH...]
       scripts/mutate.sh --clean-scratch

The untouched snapshot must pass first; then each mutant runs alone, in scratch trees under the
primary checkout's .build/scratch/.

  FILE SED_EXPR  hand-written mutants, one sed command each with its own address, such as
                 '67s/failed: /exploded: /'. An expression that changes nothing is an error.
  --diff BASE    generates mutants on the lines changed since merge-base(BASE, HEAD), uncommitted
                 edits included, in the .swift files under each PATH (from the current
                 directory; default Sources App WorkoutShared WorkoutWidgets). Each op, the OP
                 column, makes at most one mutant per line:
                   bool      true and false swapped
                   compare   ==, !=, <, <=, >, >= swapped
                   logic     && and || swapped
                   negate    an if condition negated
                   return    a guard forced to its early return
                   const     a number + 1
                   result    return x emptied to the [], [:], nil, or 0 its type takes
                   coalesce  a literal ?? default changed
                   operand   the right side of the first && or || dropped
                   always    the first a == b made true
                   clamp     a two-argument max or min dropped for the value it clamps
                 A line inside an #if os(iOS), os(macOS), canImport(UIKit), or canImport(AppKit)
                 branch the build compiles out is unreachable without a build, so a diff that
                 touches both arms of such an #if needs a run with --sim and one without, and
                 each exits 1 on the other's lines.
  --max N        runs at most N generated mutants (default 40), taking each file's first mutant
                 before any file's second; unreachable ones never count.
  --filter SEL   the tests that judge each mutant; repeatable. Without --sim: swift test --filter
                 SEL (default the whole suite). With --sim: unit, visual, ui, or a test-sim.sh
                 TEST-ID; a bare suite name means WorkoutTrackerTests/SUITE (default unit).
  --sim UDID     runs every check through the scratch tree's scripts/test-sim.sh --sim UDID.
                 swift test compiles only Sources/, so App/, WorkoutShared/, and WorkoutWidgets/
                 need --sim. Run Sources/ without --sim (seconds) and those with --sim PATH.
  --clean-scratch  removes every scratch tree no run holds, with the DerivedData its --sim builds
                 left. A tree holds about 0.3 GB of .build, and 0.8 to 1.1 GB more of DerivedData
                 once --sim has built in it; SCRATCH_SLOTS trees (default 4) reach about 6 GB.
MUTATE_TIMEOUT=N bounds each run in seconds (default 5 x the baseline's time, at least 120).

Also prints log:, mutants: (--diff), scratch:, and baseline: lines first.
The #error probe misjudges a mutant in two places: on a continuation line inside an #if
branch the build compiles out it reads SURVIVED, and inside a multi-line string literal it reads
unreachable. --diff never mutates inside a string and decides the #if branches above itself.
EOF
}
