#!/bin/bash
# Proves, through the real WorkoutStore, what a sync does to the Viewed Session.
#
# Two athletes, two homes, one doctored workbook. In both, the local cache still has the
# Current Session at w1d1 while the Sheet has gained a Set Log in a later Session, so the
# sync moves the Current Session. The athlete at the live edge must be carried forward with
# it; the athlete who browsed away must be left where they are.
#
# Usage: .claude/work/viewed-session-across-sync.sh   (from the worktree root)

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
swift build --product workout >/dev/null 2>&1
export PATH="$PWD/.build/debug:$PATH"

probe=$(mktemp -d)
live_edge=$(mktemp -d)
browsed=$(mktemp -d)
trap 'rm -rf "$probe" "$live_edge" "$browsed"' EXIT

# Which workbook cell holds w1d2's Set Logs is the parser's business, so learn it by logging
# through the app and diffing the workbook rather than hard-coding a layout assumption.
export WORKOUT_HOME="$probe"
workout init --scenario fresh-block >/dev/null
before=$(workout sheet | jq -c .cells)
workout log w1d2.e0.s0 225x5@8 >/dev/null
workout flush >/dev/null
cell=$(workout sheet | jq -r --argjson b "$before" \
  '.cells | to_entries | map(select(.value != ($b[.key] // null))) | .[0].key')
tab=$(workout sheet | jq -r .tab)
echo "the coach's Set Log for w1d2 lands in $tab!$cell"
echo

seed() {
  export WORKOUT_HOME="$1"
  workout init --scenario fresh-block >/dev/null
  jq --arg t "$tab" --arg c "$cell" '.tabs[$t].cells[$c] = "225x5@8"' \
    "$WORKOUT_HOME/workbook.json" > "$WORKOUT_HOME/workbook.tmp"
  mv "$WORKOUT_HOME/workbook.tmp" "$WORKOUT_HOME/workbook.json"
}

echo "== at the live edge, the sync carries the athlete forward =="
seed "$live_edge"
echo "before: $(workout status | jq -c '{currentSession, viewedSession: .displayedSession}')"
echo "after:  $(workout sync | jq -c '{currentSession, viewedSession}')"
echo

echo "== browsed away to w2d3, the same sync leaves the athlete there =="
seed "$browsed"
echo "before: $(workout status | jq -c '{currentSession, viewedSession: .displayedSession}')"
echo "after:  $(workout sync --viewing w2d3 | jq -c '{currentSession, viewedSession}')"
