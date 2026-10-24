# shellcheck shell=bash
# shellcheck disable=SC2034  # lane.sh and lint-build-dirs.sh read these
# Every .build/<dir> a script under scripts/ or .agents/ names, in one of two lists.
# lane.sh down copies each results dir into the lane's evidence before it removes the worktree,
# and drops each regenerable dir, which a build or a rerun makes again.
# scripts/lint-build-dirs.sh, run by scripts/lint.sh, fails on a dir in neither list.
results_dirs=(test-sim verify crap flake-hunt flake-guard mutate check-each-commit measure-host)
regenerable_dirs=(debug scratch ci-visual-diffs)
