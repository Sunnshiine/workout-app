# shellcheck shell=bash disable=SC2016
# Sourced by test-sim.sh, verify.sh, and check-each-commit.sh. Sets compile_cache_settings to the
# xcodebuild build settings that put the Swift package targets on this repo's compilation cache, one per
# host that every worktree shares (ADR-0021), or to nothing when WORKOUT_COMPILE_CACHE=0. Pass it as
# ${compile_cache_settings[@]+"${...}"}.
#
# The macros are single-quoted so Xcode expands them per target. Caching stays off in the
# WorkoutTracker project's own targets: mapped, their compiles read #filePath as /^wt/..., and an
# edit that changes a module recompiles every file of the targets importing it.
# Cache keys hold absolute paths, so the maps rename the checkout and its DerivedData dir, which holds
# SourcePackages, to fixed names in every worktree. SRCROOT would not do: in a package target it names
# the package checkout, while WORKSPACE_DIR and OBJROOT name the same dirs in every target.
compile_cache_settings=()
if [ "${WORKOUT_COMPILE_CACHE:-1}" != 0 ]; then
  compile_cache_settings=(
    'COMPILATION_CACHE_ENABLE_CACHING=$(WORKOUT_COMPILE_CACHE_$(PROJECT_NAME:c99extidentifier):default=YES)'
    WORKOUT_COMPILE_CACHE_WorkoutTracker=NO
    "COMPILATION_CACHE_CAS_PATH=$HOME/Library/Developer/Xcode/DerivedData/WorkoutTracker.CompilationCache.noindex"
    COMPILATION_CACHE_LIMIT_SIZE=2G
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES
    SWIFT_ENABLE_PREFIX_MAPPING=YES
    CLANG_ENABLE_PREFIX_MAPPING=YES
    SWIFT_ENABLE_PROJECT_PREFIX_MAPPING=YES
    CLANG_ENABLE_PROJECT_PREFIX_MAPPING=YES
  )
  compile_cache_map='$(WORKSPACE_DIR:dir:standardizepath)=/^wt $(OBJROOT:dir:standardizepath:dir:standardizepath)=/^dd'
  compile_cache_settings+=("SWIFT_OTHER_PREFIX_MAPPINGS=$compile_cache_map" "CLANG_OTHER_PREFIX_MAPPINGS=$compile_cache_map")
  unset compile_cache_map
fi
