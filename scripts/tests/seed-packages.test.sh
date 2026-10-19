#!/usr/bin/env bash
set -uo pipefail

# shellcheck source=scripts/tests/test-sim-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/test-sim-harness.sh"

project=$repo/WorkoutTracker.xcodeproj
resolved=$project/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
mkdir -p "$(dirname "$resolved")"
echo '{ "pins" : [ ], "version" : 3 }' >"$resolved"
dd=$(HOME=$root/home python3 "$repo/scripts/seed-packages.py" derived-dir "$project")
elsewhere=$root/home/Library/Developer/Xcode/DerivedData/WorkoutTracker-elsewhere
store() { "$repo/scripts/dep-store.sh" "$@"; }
foreign=/Users/other/Library/Developer/Xcode/DerivedData/WorkoutTracker-zzz/SourcePackages

# A SourcePackages tree shaped like Xcode's, whose absolute paths name the root it was resolved in.
cat >"$root/bin/make-packages" <<'STUB'
#!/bin/sh
dir=$1 named=$2
mkdir -p "$dir/checkouts/pkg/.git/objects/info" "$dir/checkouts/pkg/Sources" "$dir/repositories/pkg-1/objects" \
    "$dir/artifacts/swiftlintplugins/SwiftLintBinary/SwiftLintBinary.artifactbundle"
printf '{"object": {"artifacts": [{"path": "%s/artifacts/swiftlintplugins/SwiftLintBinary/SwiftLintBinary.artifactbundle", "targetName": "SwiftLintBinary"}], "dependencies": [{"subpath": "pkg"}]}, "version": 7}\n' "$named" >"$dir/workspace-state.json"
printf '[remote "origin"]\n\turl = %s/repositories/pkg-1\n' "$named" >"$dir/checkouts/pkg/.git/config"
printf '%s/repositories/pkg-1/objects\n' "$named" >"$dir/checkouts/pkg/.git/objects/info/alternates"
echo 'let x = 1' >"$dir/checkouts/pkg/Sources/x.swift"
chmod a-w "$dir/checkouts/pkg/.git/config" "$dir/checkouts/pkg/.git/objects/info/alternates"
STUB
# Xcode's part: write info.plist into STUB_DD, resolve when SourcePackages is absent, else reuse it.
cat >"$root/bin/xcodebuild" <<'STUB'
#!/bin/sh
[ "$1" != -version ] || { printf 'Xcode 27.0\nBuild version 27A266a\n'; exit 0; }
if [ "$1" = build-for-testing ]; then
    mkdir -p "$STUB_DD"
    python3 -c 'import plistlib, sys; plistlib.dump({"WorkspacePath": sys.argv[2]}, open(sys.argv[1], "wb"))' "$STUB_DD/info.plist" "$STUB_WORKSPACE"
    if [ -d "$STUB_DD/SourcePackages" ]; then
        echo "reused $(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["object"]["artifacts"][0]["path"])' "$STUB_DD/SourcePackages/workspace-state.json")" >>"$STUB_CALLS"
    else
        make-packages "$STUB_DD/SourcePackages" "$STUB_DD/SourcePackages"
        echo resolved >>"$STUB_CALLS"
    fi
    [ -z "${STUB_EDIT_RESOLVED:-}" ] || echo '{ "pins" : [ 1 ], "version" : 3 }' >"$STUB_EDIT_RESOLVED"
    [ -z "${STUB_BUILD_ERROR:-}" ] || { echo "$STUB_BUILD_ERROR"; echo '** TEST BUILD FAILED **'; exit 65; }
    echo '** TEST BUILD SUCCEEDED **'
    exit 0
fi
printf '◇ Test run started.\n✔ Test run with 3 tests in 1 suite passed after 0.1 seconds.\n** TEST EXECUTE SUCCEEDED **\n'
STUB
chmod +x "$root/bin/make-packages" "$root/bin/xcodebuild"

run() {
    rm -f "$root/calls"
    STUB_DD=${STUB_DD:-$dd} STUB_WORKSPACE=$project STUB_CALLS=$root/calls HOME=$root/home PATH="$root/bin:$PATH" \
        "$repo/scripts/test-sim.sh" --sim "$sim" unit >"$root/out" 2>"$root/err"
    status=$?
}
calls() { cat "$root/calls" 2>/dev/null; }
entries() { store list | cut -f1; }
seeded_line() { grep -c '^seed-packages: seeded ' "$root/err"; }
expect() {
    if [ "$2" = "$3" ]; then ok "$1"; else
        bad "$1"
        printf '    got:  %s\n    want: %s\n    stderr:\n%s\n' "$2" "$3" "$(cat "$root/err")"
    fi
}
# Puts a foreign producer's packages in the store under the key this project's builds use.
store_foreign() {
    rm -rf "$WORKOUT_DEP_STORE" "$root/foreign"
    make-packages "$root/foreign" "$foreign"
    # shellcheck disable=SC2016  # sh -c expands them
    store publish "$key" sh -c 'cp -R "$0"/. "$DEP_STORE_OUT"' "$root/foreign" 2>/dev/null
}
tree_sum() { (cd "$1" && find . -type f | sort | xargs shasum); }
PATH="$root/bin:$PATH"

run
key=$(entries)
expect "a fresh lane with an empty store resolves the packages, then publishes what it resolved" \
    "$status $(calls) $(entries | grep -c .) $(/usr/bin/grep -c "$dd/SourcePackages/artifacts" "$WORKOUT_DEP_STORE/entries/$key/payload/workspace-state.json")" \
    "0 resolved 1 1"

store_foreign
rm -rf "$dd"
run
expect "the next fresh lane clones them, and Xcode reuses them, repointed at its own DerivedData" \
    "$status $(seeded_line) | $(calls)" \
    "0 1 | reused $dd/SourcePackages/artifacts/swiftlintplugins/SwiftLintBinary/SwiftLintBinary.artifactbundle"
expect "no file the build reads still names the producer's DerivedData: not the read-only git origin, not the object alternates" \
    "$(/usr/bin/grep -rl "$foreign" "$dd/SourcePackages") | $(cat "$dd/SourcePackages/checkouts/pkg/.git/objects/info/alternates") $(stat -f %Lp "$dd/SourcePackages/checkouts/pkg/.git/config")" \
    " | $dd/SourcePackages/repositories/pkg-1/objects 444"
expect "the store's entry keeps the producer's paths, since the lane rewrote its own clone" \
    "$(/usr/bin/grep -rl "$foreign" "$WORKOUT_DEP_STORE/entries/$key/payload" | grep -c .) $(ls -d "$dd"/SourcePackages.seeding.* 2>/dev/null)" "3 "

echo 'local edit' >"$dd/SourcePackages/checkouts/pkg/Sources/x.swift"
before=$(tree_sum "$dd/SourcePackages")
rm -rf "$WORKOUT_DEP_STORE"
run
expect "a lane whose DerivedData already holds SourcePackages is untouched and publishes nothing" \
    "$status $(calls | cut -d' ' -f1) $(grep -c seed-packages "$root/err") $(entries | grep -c .) $([ "$(tree_sum "$dd/SourcePackages")" = "$before" ] && echo same)" \
    "0 reused 0 0 same"

rm -rf "$dd"
WORKOUT_SEED_PACKAGES=0 run
expect "WORKOUT_SEED_PACKAGES=0 resolves cold and publishes nothing" \
    "$status $(calls) $(entries | grep -c .) $(grep -c seed-packages "$root/err")" "0 resolved 0 0"

store_foreign
rm -rf "$dd"
mkdir -p "$dd/SourcePackages.seeding.999999/checkouts"
run
expect "a staging dir an interrupted seed left is swept, and the lane seeds" \
    "$status $(seeded_line) $(calls | cut -d' ' -f1) $(ls -d "$dd"/SourcePackages.seeding.* 2>/dev/null)" "0 1 reused "

rm -rf "$dd" "$elsewhere"
STUB_DD=$elsewhere run
expect "when Xcode builds elsewhere, the guessed DerivedData dir is removed and nothing is published from it" \
    "$status $(calls) $([ -e "$dd" ] && echo left || echo gone) $(entries | grep -c .) | $(tail -1 "$root/err")" \
    "0 resolved gone 1 | seed-packages: Xcode did not build in $dd, so it was not this project's DerivedData; removed the packages seeded there"

rm -rf "$dd" "$elsewhere"
mkdir -p "$dd"
python3 -c 'import plistlib, sys; plistlib.dump({"WorkspacePath": "/Users/x/Other.xcodeproj"}, open(sys.argv[1], "wb"))' "$dd/info.plist"
before=$(tree_sum "$dd")
STUB_DD=$elsewhere run
expect "a DerivedData dir whose info.plist names another project is never touched" \
    "$status $([ "$(tree_sum "$dd")" = "$before" ] && echo same) $(ls "$dd") | $(head -1 "$root/err")" \
    "0 same info.plist | seed-packages: $dd belongs to another project; resolving packages without the store"

rm -rf "$dd" "$elsewhere"
STUB_BUILD_ERROR="$repo/App/Views/Today.swift:3:5: error: cannot find 'x' in scope" run
expect "a seeded build that fails on an app error keeps the seeded packages" \
    "$status $(seeded_line) $([ -d "$dd/SourcePackages" ] && echo kept)" "65 1 kept"

rm -rf "$dd"
STUB_BUILD_ERROR="xcodebuild: error: Could not resolve package dependencies:" run
expect "a seeded build that fails on a package error removes the seed" \
    "$status $([ -e "$dd/SourcePackages" ] && echo kept || echo removed) $(grep -c 'the next run resolves them cold' "$root/err")" "65 removed 1"
run
expect "and the next run resolves cold though the store holds the entry" "$status $(calls) $(seeded_line)" "0 resolved 0"

rm -rf "$dd" "$WORKOUT_DEP_STORE"
STUB_EDIT_RESOLVED=$resolved run
expect "a build that changed Package.resolved publishes nothing, since the key no longer describes it" \
    "$status $(entries | grep -c .) $(grep -c 'not publishing' "$root/err")" "0 0 1"
echo '{ "pins" : [ ], "version" : 3 }' >"$resolved"

rm -rf "$dd"
touch "$root/not-a-dir"
WORKOUT_DEP_STORE=$root/not-a-dir run
expect "a store that cannot be written never fails the run" \
    "$status $(calls) $(grep -c 'publishing to the dependency store failed' "$root/err") $(tail -1 "$root/out" | grep -o 'exit=0')" \
    "0 resolved 1 exit=0"

# Pairs copied from info.plist files Xcode 27 wrote on this Mac.
names=$(for p in /Users/sunnypatel/Projects/workout-app/WorkoutTracker.xcodeproj:eebwoxxdcimjyzfccdjmhrvqvxpq \
    /tmp/chalk-proof-tip/WorkoutTracker.xcodeproj:hhgszykzxtogweadgkkuppkaeccr \
    /Users/sunnypatel/Projects/workout-app/.build/scratch/2/WorkoutTracker.xcodeproj:gornefpdeeysdhfodkazajgmjawj; do
    got=$(python3 "$repo/scripts/seed-packages.py" derived-dir "${p%%:*}")
    [ "${got##*/}" = "WorkoutTracker-${p##*:}" ] && echo match
done | grep -c match)
expect "the DerivedData name matches the one Xcode wrote for each project path" "$names" 3
mkdir -p "$root/x/W.xcodeproj"
expect "a leading /private is dropped when the rest exists, as Xcode's path standardizing does" \
    "$(python3 "$repo/scripts/seed-packages.py" derived-dir "/private$root/x/W.xcodeproj")" \
    "$(python3 "$repo/scripts/seed-packages.py" derived-dir "$root/x/W.xcodeproj")"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
