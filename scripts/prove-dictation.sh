#!/bin/bash
# Proves that speech lands in the Sheet: each phrase is spoken by macOS `say` in two voices, heard
# by `workout hear` through the speech model the app's mic uses, written under the Dictation write
# policy, and flushed to the workbook.
#
# Usage: scripts/prove-dictation.sh   (from the worktree root; macOS 26 or later)

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
swift build --product workout >/dev/null 2>&1
export PATH="$PWD/.build/debug:$PATH"

voices=("Samantha" "Daniel")
# Set, then phrase. "same again" follows the Set it repeats, in the same Exercise.
phrases=(
  "w1d1.e0.s0|185 for 5 at 8"
  "w1d1.e0.s1|same again"
  "w1d1.e0.s2|135 for 4, 8 reps, RPE 9"
  "w1d2.e0.s0|225 for 3 at RPE 9.5"
  "w1d2.e0.s1|185 or 5"
  "w1d1.e1.s0|10 for 12 at 8"
  "w1d1.e1.s1|135 for 45"
  "w1d2.e1.s0|bodyweight for 12 at 7"
  "w1d2.e1.s1|skip"
)

for voice in "${voices[@]}"; do
  say -v '?' | grep "^$voice " >/dev/null || { echo "voice $voice is not installed; add it in System Settings > Accessibility > Spoken Content" >&2; exit 1; }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
table="$work/table.tsv"
: > "$work/unwritten.txt"
printf 'phrase\tvoice\tset\ttop transcript\toutcome\texit\tSet Log written\n' > "$table"

for voice in "${voices[@]}"; do
  export WORKOUT_HOME="$work/home-$voice"
  workout init --scenario fresh-block >/dev/null
  workout sheet | jq -c .cells > "$work/before-$voice.json"
  for entry in "${phrases[@]}"; do
    set_address=${entry%%|*}
    phrase=${entry#*|}
    recording="$work/$voice-$set_address.aiff"
    say -v "$voice" -o "$recording" "$phrase"
    report=$(workout hear "$set_address" "$recording" 2>/dev/null) && status=0 || status=$?
    if [[ -z $report ]]; then
      printf '%s\t%s\t%s\t-\tno report\t%s\t-\n' "$phrase" "$voice" "$set_address" "$status" >> "$table"
      continue
    fi
    jq -r --arg phrase "$phrase" --arg voice "$voice" --arg set "$set_address" --arg status "$status" \
      '[$phrase, $voice, $set, .heard,
        (.outcome + (if .rejection then " (" + .rejection.reason + ")" elif .missing then " (" + (.missing | join(", ")) + ")" else "" end)),
        $status, (if .outcome == "logged" then .setLog elif .outcome == "skipped" then "skip" else "-" end)] | @tsv' \
      <<< "$report" >> "$table"
    jq -r --arg phrase "$phrase" --arg voice "$voice" \
      'select(.outcome != "logged" and .outcome != "skipped")
        | "\($voice), \"\($phrase)\": \(.candidates | map("\"\(.)\"") | join(" | "))"' \
      <<< "$report" >> "$work/unwritten.txt"
  done
done

column -t -s $'\t' "$table"
echo
echo "== every transcript the model heard, most likely first, for each phrase that wrote nothing =="
cat "$work/unwritten.txt"

for voice in "${voices[@]}"; do
  export WORKOUT_HOME="$work/home-$voice"
  echo
  echo "== $voice: $(workout flush | jq -r '"\(.written) of \(.attempted) writes flushed"'); the cells that changed =="
  workout sheet | jq -r --slurpfile before "$work/before-$voice.json" \
    '.tab as $tab | .cells | to_entries | map(select(.value != ($before[0][.key] // null)))
      | sort_by(.key | [capture("(?<c>[A-Z]+)(?<r>[0-9]+)") | (.r | tonumber), (.c | length), .c])
      | .[] | "\($tab)!\(.key)  \(.value)"'
done
