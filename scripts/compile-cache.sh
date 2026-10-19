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

# Whatever WORKOUT_COMPILE_CACHE says, the WorkoutTracker project's targets build without an index
# store: no lane tool reads one, and writing it into a fresh DerivedData cost a lane's first unit
# build about 7 of its 153 CPU seconds. Scoped like the cache, so package compiles and their cache
# keys stay as they were.
compile_cache_settings+=(
  'COMPILER_INDEX_STORE_ENABLE=$(WORKOUT_INDEX_STORE_$(PROJECT_NAME:c99extidentifier):default=Default)'
  WORKOUT_INDEX_STORE_WorkoutTracker=NO
)

# WorkoutTrackerTests compiles in 6 batch jobs, not one per core. Each job type-checks its first
# Swift Testing macro expansion for about 1.5 CPU seconds whatever else it holds, so 12 jobs cost a
# fresh unit build about 21 more CPU seconds than 6, for about 3 seconds less wall time.
compile_cache_settings+=(
  'OTHER_SWIFT_FLAGS=$(inherited) $(WORKOUT_SWIFT_FLAGS_$(TARGET_NAME:c99extidentifier))'
  'WORKOUT_SWIFT_FLAGS_WorkoutTrackerTests=-driver-batch-count 6'
)
