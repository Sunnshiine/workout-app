#!/bin/bash
# Scratch hill-climb harness. Builds once, then runs each line of .hc/configs on the same runner.
set -uo pipefail
out=$PWD/.hc-out
mkdir -p "$out"
summary=$out/summary.tsv
hc() { printf 'HC\t%s\n' "$*" | tee -a "$summary"; }
now() { python3 -c 'import time; print(f"{time.time():.1f}")'; }
since() { python3 -c "print(f'{$(now) - $1:.0f}')"; }

hc "host ncpu=$(sysctl -n hw.ncpu) mem=$(( $(sysctl -n hw.memsize) / 1073741824 ))G model=$(sysctl -n hw.model) xcode=$(xcodebuild -version | tr '\n' ' ')"
t=$(now)
udid=$(scripts/ensure-simulator.sh "$BASELINE_DEVICE" "$BASELINE_RUNTIME" | tail -1)
hc "ensure-simulator secs=$(since "$t") udid=$udid"

[ ! -f .hc/preboot ] || { xcrun simctl boot "$udid" 2>/dev/null; hc "preboot started"; }
t=$(now)
xcodebuild build-for-testing -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$RUNNER_TEMP/DerivedData" \
    -clonedSourcePackagesDirPath "$RUNNER_TEMP/SourcePackages" \
    -onlyUsePackageVersionsFromResolvedFile \
    -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_CAS_PATH="$RUNNER_TEMP/CompilationCache" >"$out/build.log" 2>&1
hc "build rc=$? secs=$(since "$t")"
t=$(now)
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1
hc "boot secs=$(since "$t")"
xctestrun=$(ls "$RUNNER_TEMP"/DerivedData/Build/Products/*.xctestrun | head -1)

run() {
    local name=$1 rep=$2
    shift 2
    local bundle=$out/$name-$rep.xcresult t rc
    t=$(now)
    xcodebuild test-without-building -xctestrun "$xctestrun" -destination "platform=iOS Simulator,id=$udid" \
        -resultBundlePath "$bundle" -collect-test-diagnostics never "$@" >"$out/$name-$rep.log" 2>&1
    rc=$?
    local wall
    wall=$(since "$t")
    local first
    first=$(grep -m1 -n "Test Suite 'All tests' started\|Test case .* started on\|Test Case .* started" "$out/$name-$rep.log" | cut -d: -f1)
    xcrun xcresulttool get test-results summary --path "$bundle" --compact >"$out/$name-$rep.summary.json" 2>/dev/null
    xcrun xcresulttool get test-results tests --path "$bundle" --compact >"$out/$name-$rep.tests.json" 2>/dev/null
    local counts
    counts=$(python3 .hc/counts.py "$out/$name-$rep.summary.json" "$out/$name-$rep.tests.json")
    hc "run $name rep=$rep rc=$rc wall=$wall $counts load=$(sysctl -n vm.loadavg | awk '{print $2}')"
}

while IFS='|' read -r name reps args; do
    case $name in '' | \#*) continue ;; esac
    for ((r = 1; r <= reps; r++)); do
        # shellcheck disable=SC2086
        run "$name" "$r" $args
    done
done <.hc/configs
cat "$summary"
