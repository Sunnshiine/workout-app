# shellcheck shell=bash
usage() {
    cat <<'EOF'
Usage: scripts/mutate.sh [--sim UDID] [--filter SEL]... FILE SED_EXPR [SED_EXPR...]
       scripts/mutate.sh [--sim UDID] [--filter SEL]... [--max N] --diff BASE [PATH...]
       scripts/mutate.sh --clean-scratch

Proves that a test pins a line: each mutant is one change to the code, and some test must fail on it.
Every mutant builds and runs in a scratch tree under the primary checkout's .build/scratch/, never
in your worktree. Your uncommitted and untracked files are part of what gets mutated. The untouched
snapshot must pass first; then each mutant runs alone.

  FILE SED_EXPR  hand-written mutants, one sed command each with its own address, such as
                 '67s/failed: /exploded: /'. An expression that changes nothing is an error.
  --diff BASE    generates mutants on the lines changed since merge-base(BASE, HEAD), uncommitted
                 edits included: true/false flips, comparison and &&/|| swaps, if-negation, guard
                 forced to its early return, a number + 1, in the .swift files under each PATH
                 (from the current directory; default Sources App WorkoutShared WorkoutWidgets).
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

Prints log:, mutants: (--diff), scratch:, and baseline: lines, then a row per mutant as it ends:
  OUTCOME  FILE:LINE  OP  CHANGE  FIRST-KILLER +N | REASON
  killed       a test failed, crashed, or the run timed out; results.tsv lists every killer
  flaky        every killer also failed on one rerun of the untouched snapshot after the rows
  SURVIVED     no test failed, and an #error on the line breaks the build (grep '^SURVIVED')
  nocompile    the compiler rejects the mutated file
  unreachable  this build never compiles the line (#if, no target; App/ needs --sim)
  error        the runner failed without naming a failing test, or the build failed elsewhere
  not run      --max left it out
The #error probe misjudges a mutant in two places: on a continuation line inside an #if
branch the build compiles out it reads SURVIVED, and inside a multi-line string literal it reads
unreachable. --diff never mutates inside a string and decides the #if branches above itself.
Exits 0 when every mutant was killed (a generated nocompile does not count); 1 when any was flaky,
SURVIVED, unreachable, an error, or a hand-written nocompile, when --max left any unrun, or when
none was killed; 2 on usage or a failing baseline; 75 when every scratch tree or the simulator is
busy (the rows so far print first).
EOF
}
