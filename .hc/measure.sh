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
xctestrun=$(ls "$RUNNER_TEMP"/DerivedData/Build/Products/*.xctestrun | head -1)

slim() {
    local store=/private/var/tmp/com.apple.CoreSimulator.SimDevice.$1
    mkdir -p -m 700 "$store"
    python3 - "$store/disabled.plist" scripts/sim-pool-disabled-jobs.txt <<'PY'
import os, plistlib, sys
store, jobs = sys.argv[1:]
labels = [line.split("#")[0].strip() for line in open(jobs)]
entries = plistlib.load(open(store, "rb")) if os.path.exists(store) else {}
entries.update((label, True) for label in labels if label)
plistlib.dump(entries, open(store, "wb"))
PY
}

run() {
    local name=$1 rep=$2 boot=$3
    shift 3
    local bundle=$out/$name-$rep.xcresult t rc dev
    xcrun simctl shutdown all >/dev/null 2>&1
    dev=$(xcrun simctl create "hc-$name-$rep" "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro" "com.apple.CoreSimulator.SimRuntime.iOS-27-0")
    [ "$boot" != slim ] || slim "$dev"
    t=$(now)
    xcrun simctl boot "$dev" && xcrun simctl bootstatus "$dev" -b >/dev/null 2>&1
    local bootsecs
    bootsecs=$(since "$t")
    t=$(now)
    xcodebuild test-without-building -xctestrun "$xctestrun" -destination "platform=iOS Simulator,id=$dev" \
        -resultBundlePath "$bundle" -collect-test-diagnostics never "$@" >"$out/$name-$rep.log" 2>&1
    rc=$?
    local wall
    wall=$(since "$t")
    xcrun xcresulttool get test-results summary --path "$bundle" --compact >"$out/$name-$rep.summary.json" 2>/dev/null
    xcrun xcresulttool get test-results tests --path "$bundle" --compact >"$out/$name-$rep.tests.json" 2>/dev/null
    local counts
    counts=$(python3 .hc/counts.py "$out/$name-$rep.summary.json" "$out/$name-$rep.tests.json")
    hc "run $name rep=$rep boot=$boot bootsecs=$bootsecs rc=$rc wall=$wall $counts"
    xcrun simctl shutdown "$dev" >/dev/null 2>&1
    xcrun simctl delete "$dev" >/dev/null 2>&1
}

while IFS='|' read -r name reps boot args; do
    case $name in '' | \#*) continue ;; esac
    for ((r = 1; r <= reps; r++)); do
        # shellcheck disable=SC2086
        run "$name" "$r" "$boot" $args
    done
done <.hc/configs
cat "$summary"
