#!/usr/bin/env bash
# Lint every tree .swiftlint.yml claims, without building the app.
#
# The app target runs SwiftLint through SwiftLintBuildToolPlugin, so `App` and
# `Sources/WorkoutTracker` are linted on every Xcode build. `Sources/WorkoutCLI` and `Tests` belong
# to no target that carries the plugin, so until this script existed they were never linted anywhere
# (issue #607). This runs the same binary the plugin runs, over the same config, with no build.
#
# The run takes no path arguments on purpose. SwiftLint's `included:` overrides command-line paths,
# so a script that passes its own list lints something other than what it names. With no arguments
# the config alone decides what is linted, and SwiftLint exits 0 however little that is. So after a
# clean lint the check below reads the files SwiftLint actually linted, from its `--benchmark` list.
# A tree is an `included:` root, or a directory directly inside one that holds a Swift file git
# knows about, and every tree must have at least one linted file. That refuses both ways a tree can
# leave the gate: an `included:` root that is misspelled or moved, and an `excluded:` entry that
# covers a whole tree. A narrow exclusion passes. `**/Generated` drops generated code inside a tree,
# and the rest of the tree is still linted.
#
#   scripts/lint.sh                  lint (what CI runs)
#   scripts/lint.sh --fix            autocorrect what SwiftLint can, then lint
#   scripts/lint.sh --print-version  print the pinned SwiftLint version and exit
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG=".swiftlint.yml"
RESOLVED="WorkoutTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
CACHE_DIR="${SWIFTLINT_CACHE_DIR:-$HOME/.cache/workout-swiftlint}"

MODE="lint"
case "${1:-}" in
    --fix) MODE="fix" ;;
    --print-version) MODE="print-version" ;;
    "") ;;
    *)
        echo "usage: scripts/lint.sh [--fix|--print-version]" >&2
        exit 64
        ;;
esac

# The version the Xcode build plugin resolves to. Xcode writes this file, so when the plugin's
# package moves this script follows it and there is no second place to edit. To re-pin: bump
# SwiftLintPlugins in Xcode, let it rewrite Package.resolved, and commit that.
# `|| true` keeps a missing pin from aborting at this assignment, so the message below is reachable.
VERSION="$(
    grep -A 8 '"identity" : "swiftlintplugins"' "$RESOLVED" 2>/dev/null |
        sed -n 's/.*"version" *: *"\([^"]*\)".*/\1/p' |
        head -1 || true
)"
if [ -z "$VERSION" ]; then
    echo "error: $RESOLVED has no swiftlintplugins pin, so there is no version to agree with." >&2
    echo "       Open the project in Xcode to resolve packages, then commit Package.resolved." >&2
    exit 1
fi

if [ "$MODE" = "print-version" ]; then
    echo "$VERSION"
    exit 0
fi

# SwiftLintPlugins is a thin wrapper: its Package.swift declares one binaryTarget pointing at this
# exact artifact bundle. Fetching it here is not "the same version number" as the plugin, it is the
# same binary, so CI and the app build cannot disagree about what a violation is.
BUNDLE_URL="https://github.com/realm/SwiftLint/releases/download/$VERSION/SwiftLintBinary.artifactbundle.zip"
SWIFTLINT="$CACHE_DIR/$VERSION/SwiftLintBinary.artifactbundle/macos/swiftlint"

if [ ! -x "$SWIFTLINT" ]; then
    echo "==> Fetching SwiftLint $VERSION"
    mkdir -p "$CACHE_DIR/$VERSION"
    curl -fsSL -o "$CACHE_DIR/$VERSION/bundle.zip" "$BUNDLE_URL"
    unzip -qo "$CACHE_DIR/$VERSION/bundle.zip" -d "$CACHE_DIR/$VERSION"
    chmod +x "$SWIFTLINT"
fi

REPORTED="$("$SWIFTLINT" version)"
if [ "$REPORTED" != "$VERSION" ]; then
    echo "error: $SWIFTLINT reports $REPORTED but the project pins $VERSION." >&2
    echo "       CI and the app build would disagree about what a violation is. Clear $CACHE_DIR." >&2
    exit 1
fi

# SwiftLint skips an `included:` entry that matches nothing and still exits 0. That is how this
# config came to claim three trees while linting one, and why the tree check starts from these roots.
included_roots() {
    awk '/^included:/ { inside = 1; next }
         inside && /^[^[:space:]#]/ { exit }
         inside && /^[[:space:]]*-[[:space:]]/ {
             sub(/^[[:space:]]*-[[:space:]]*/, "")
             gsub(/^"|"$/, "")
             print
         }' "$CONFIG"
}

ROOTS="$(included_roots)"
if [ -z "$ROOTS" ]; then
    echo "error: $CONFIG has no 'included:' entries, so this run would lint nothing." >&2
    exit 1
fi

# Reads SwiftLint's benchmark file list. Prints `typo <root>` for a root with no Swift file that
# SwiftLint linted or git knows about, and `widened <tree>` for a tree whose Swift files SwiftLint
# linted none of. A root with no linted file is reported alone, not again for each tree inside it.
tree_failures() {
    {
        printf '%s\n' "$ROOTS" | sed 's/^/root /'
        git -c core.quotePath=false ls-files --cached --others --exclude-standard -- '*.swift' |
            sed 's/^/known /'
        sed 's/^[^:]*: /linted /' "$1"
    } | awk -v prefix="$ROOT/" '
        $1 == "root" { roots[++n] = substr($0, 6); next }
        {
            path = substr($0, length($1) + 2)
            if (index(path, prefix) == 1) path = substr(path, length(prefix) + 1)
            for (i = 1; i <= n; i++) {
                r = roots[i]
                if (path != r && index(path, r "/") != 1) continue
                count[$1, r]++
                rest = substr(path, length(r) + 2)
                slash = index(rest, "/")
                if (slash == 0) continue
                tree = r "/" substr(rest, 1, slash - 1)
                count[$1, tree]++
                if ($1 == "known" && !(tree in seen)) { seen[tree] = 1; trees[++t] = tree; parent[t] = r }
            }
        }
        END {
            for (i = 1; i <= n; i++) {
                r = roots[i]
                if (count["linted", r]) {
                    for (j = 1; j <= t; j++)
                        if (parent[j] == r && !count["linted", trees[j]]) print "widened " trees[j]
                } else if (count["known", r]) {
                    print "widened " r
                } else {
                    print "typo " r
                }
            }
        }'
}

if [ "$MODE" = "fix" ]; then
    "$SWIFTLINT" --fix
fi

# No --config on purpose. Passing one turns off SwiftLint's nested-config discovery, and
# Tests/.swiftlint.yml carries the rules a test body is exempt from. Run from ROOT, SwiftLint picks
# up $CONFIG by itself and merges the nested file into it.
#
# --strict fails on warnings too. Every tree is at zero, and a warning nobody gates on is the state
# this gate exists to end.
#
# --benchmark writes benchmark_files_<timestamp>.txt into the working directory, one
# `<seconds>: <absolute path>` line per linted file, and a rules file beside it.
rm -f "$ROOT"/benchmark_files_*.txt "$ROOT"/benchmark_rules_*.txt
trap 'rm -f "$ROOT"/benchmark_files_*.txt "$ROOT"/benchmark_rules_*.txt' EXIT
echo "==> SwiftLint $VERSION over $CONFIG 'included:'"
"$SWIFTLINT" lint --strict --quiet --benchmark

LINTED="$(ls "$ROOT"/benchmark_files_*.txt 2>/dev/null || true)"
if [ ! -f "$LINTED" ]; then
    echo "error: SwiftLint --benchmark left no benchmark_files_*.txt, so nothing shows what it linted." >&2
    exit 1
fi

FAILURES="$(tree_failures "$LINTED")"
while read -r kind tree; do
    case "$kind" in
        typo)
            echo "error: $CONFIG 'included:' names '$tree', which holds no Swift file." >&2
            echo "       SwiftLint would skip it and still exit 0, so the gate would lint less than it" >&2
            echo "       claims. Correct the path or drop the entry." >&2
            ;;
        widened)
            echo "error: '$tree' holds Swift files, but SwiftLint linted none of them." >&2
            echo "       An 'excluded:' entry in $CONFIG covers the whole tree, so the gate would lint" >&2
            echo "       less than it claims. Narrow the entry to the generated or vendored path inside the tree." >&2
            ;;
    esac
done <<FAILURES_EOF
$FAILURES
FAILURES_EOF
if [ -n "$FAILURES" ]; then
    exit 1
fi
echo "==> Clean"
