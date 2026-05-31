#!/usr/bin/env bash
#
# snapshot.sh — build the app for the iOS simulator with the UITEST fixture enabled,
# launch it, and capture a screenshot of the seeded SessionView.
#
# The Ralph loop calls this to get a visual artifact for View-touching changes, since
# `swift test` cannot exercise SwiftUI views and a normal launch hits the Google sign-in
# wall. The fixture (-UITEST_FIXTURE) boots straight into a populated session in-memory.
#
# Usage:   ralph/snapshot.sh [output.png]
# Env:     SIM_DEVICE (default "iPhone 17 Pro"), SCHEME, BUNDLE_ID, UITEST_ARGS
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# PROJECT_DIR lets the loop point this at a per-issue git worktree instead of main.
PROJECT_DIR="${PROJECT_DIR:-$DEFAULT_ROOT}"
cd "$PROJECT_DIR"

SIM_DEVICE="${SIM_DEVICE:-iPhone 17 Pro}"
SCHEME="${SCHEME:-WorkoutTracker}"
BUNDLE_ID="${BUNDLE_ID:-com.sunnypatel.WorkoutTracker}"
DD="${DD:-$PROJECT_DIR/.ralph-dd}"
OUT="${1:-$DEFAULT_ROOT/ralph/.artifacts/screenshot.png}"
mkdir -p "$(dirname "$OUT")"

# New Swift files are only picked up by the app target after the project is regenerated.
echo "==> xcodegen generate"
xcodegen generate >/dev/null

echo "==> Building $SCHEME for '$SIM_DEVICE' (Debug, simulator)"
xcodebuild -project WorkoutTracker.xcodeproj -scheme "$SCHEME" -configuration Debug \
  -destination "platform=iOS Simulator,name=$SIM_DEVICE" \
  -derivedDataPath "$DD" build >/dev/null

APP="$(find "$DD/Build/Products" -name "$SCHEME.app" -path '*Debug-iphonesimulator*' | head -1)"
[ -n "$APP" ] || { echo "ERROR: built .app not found under $DD" >&2; exit 1; }

echo "==> Booting '$SIM_DEVICE' (waits until ready)"
xcrun simctl bootstatus "$SIM_DEVICE" -b >/dev/null 2>&1 || xcrun simctl boot "$SIM_DEVICE" || true

read -r -a route_args <<< "${UITEST_ARGS:--UITEST_SESSION}"
launch_args=(-UITEST_FIXTURE "${route_args[@]}")

echo "==> Installing + launching with ${launch_args[*]}"
xcrun simctl uninstall "$SIM_DEVICE" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$SIM_DEVICE" "$APP"
xcrun simctl launch "$SIM_DEVICE" "$BUNDLE_ID" "${launch_args[@]}" >/dev/null

# Let SwiftUI render the seeded session before capturing.
sleep 4

echo "==> Capturing screenshot -> $OUT"
xcrun simctl io "$SIM_DEVICE" screenshot "$OUT" >/dev/null
echo "$OUT"
