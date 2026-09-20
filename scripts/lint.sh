#!/usr/bin/env bash
# Lint every tree .swiftlint.yml claims, without building the app.
#
# The app target runs SwiftLint through SwiftLintBuildToolPlugin, so `WorkoutTracker` is linted on
# every Xcode build. `WorkoutCLI` and `Tests` sit in the config's `included:` list but belong to no
# target that carries the plugin, so until this script existed they were never linted anywhere
# (issue #607). This runs the same binary the plugin runs, over the same config, with no build.
#
# The run takes no path arguments on purpose. SwiftLint's `included:` overrides command-line paths,
# so `included:` is the only thing that decides what gets linted, and a tree added to it cannot go
# unlinted again.
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
VERSION="$(
    grep -A 8 '"identity" : "swiftlintplugins"' "$RESOLVED" |
        sed -n 's/.*"version" *: *"\([^"]*\)".*/\1/p' |
        head -1
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

if [ "$MODE" = "fix" ]; then
    "$SWIFTLINT" --fix
fi

# No --config on purpose. Passing one turns off SwiftLint's nested-config discovery, and
# Tests/.swiftlint.yml carries the rules a test body is exempt from. Run from ROOT, SwiftLint picks
# up $CONFIG by itself and merges the nested file into it.
#
# --strict fails on warnings too. Every tree is at zero, and a warning nobody gates on is the state
# this gate exists to end.
echo "==> SwiftLint $VERSION over $CONFIG 'included:'"
"$SWIFTLINT" lint --strict --quiet
echo "==> Clean"
