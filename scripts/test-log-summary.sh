#!/usr/bin/env bash
# Usage: scripts/test-log-summary.sh LOG
# Prints what test-log-summary.awk reads from a swift test or xcodebuild log, then the open GitHub
# issue whose title names each failing test, then, under GitHub Actions, one ::error annotation per
# issue a test recorded. Exits as the awk does: 0 when a test run finished, 1 when none did. The gh
# lookup never changes that; it is skipped when gh fails and given up on after WORKOUT_ISSUE_WAIT
# seconds (10).
set -uo pipefail

dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT

awk -f "$dir/test-log-summary.awk" "$1" | uniq >"$work/summary"
ran=${PIPESTATUS[0]}
cat "$work/summary"

issues=
bound=${WORKOUT_ISSUE_WAIT:-10}
if grep -q -e ' recorded an issue ' -e ' failed after ' -e '^Failing tests:' "$work/summary" &&
    command -v gh >/dev/null; then
    GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 gh issue list --state open --limit 1000 \
        --json number,title --jq '.[] | "\(.number)\t\(.title)"' </dev/null >"$work/issues" 2>/dev/null &
    gh=$!
    for ((tenths = 0; tenths < bound * 10; tenths++)); do
        kill -0 "$gh" 2>/dev/null || break
        sleep 0.1
    done
    kill "$gh" 2>/dev/null && echo "no issue lookup: gh issue list gave no answer in $bound s"
    wait "$gh" && issues=$work/issues
fi
paths=
if [ "${GITHUB_ACTIONS:-}" = true ]; then
    git -C "$dir/.." ls-files '*.swift' >"$work/paths" 2>/dev/null && paths=$work/paths
fi

awk -v issues="$issues" -v paths="$paths" -v actions="${GITHUB_ACTIONS:-}" '
function failing(name) {
  if (name ~ /^".*"$/) name = substr(name, 2, length(name) - 2)
  else {
    if (name ~ /^-\[[^ ]+ .+\]$/) { sub(/^-\[[^ ]+ /, "", name); sub(/\]$/, "", name) }
    sub(/\(.*/, "", name)
    sub(/.*\./, "", name)
  }
  if (name != "" && !(name in seen)) { seen[name] = 1; order[++count] = name }
  return name
}
function titled(title, name,    rest, at) {
  rest = " " title " "
  while ((at = index(rest, name)) > 0) {
    if (substr(rest, at - 1, 1) !~ /[A-Za-z0-9_]/ && substr(rest, at + length(name), 1) !~ /[A-Za-z0-9_]/) return 1
    rest = substr(rest, at + 1)
  }
  return 0
}
function escape(text, property) {
  gsub(/%/, "%25", text); gsub(/\r/, "%0D", text); gsub(/\n/, "%0A", text)
  if (property) { gsub(/:/, "%3A", text); gsub(/,/, "%2C", text) }
  return text
}
BEGIN {
  while (issues != "" && (getline line < issues) > 0) {
    number[++known] = substr(line, 1, index(line, "\t") - 1)
    title[known] = substr(line, index(line, "\t") + 1)
  }
  while (paths != "" && (getline line < paths) > 0) {
    base = line
    sub(/.*\//, "", base)
    path[base] = base in path ? "" : line
  }
}
/^↳ / && open { sub(/^↳ /, ""); text[notes] = text[notes] "\n" $0; next }
{ open = 0 }
/^[^ ]+ Test .* recorded an issue / {
  name = $0
  sub(/^[^ ]+ Test /, "", name)
  sub(/ recorded an issue .*/, "", name)
  name = failing(name)
  if (actions != "true" || !match($0, / at [^ ]+\.swift:[0-9]+:[0-9]+: /)) next
  split(substr($0, RSTART + 4, RLENGTH - 6), at, ":")
  file = path[at[1]] == "" ? "" : "file=" escape(path[at[1]], 1) ","
  where[++notes] = file "line=" at[2] ",col=" at[3] ",title=" escape(name " failed", 1)
  test[notes] = name
  text[notes] = substr($0, RSTART + RLENGTH)
  open = 1
  next
}
/^[^ ]+ Test .* failed after / && !/^[^ ]+ Test run with / {
  name = $0
  sub(/^[^ ]+ Test /, "", name)
  sub(/ (with [0-9]+ test cases? )?failed after .*/, "", name)
  failing(name)
  next
}
/^Failing tests:/ { block = 1; next }
block && /^\t/ { name = $0; sub(/^\t+/, "", name); failing(name); next }
{ block = 0 }
END {
  for (i = 1; i <= count; i++) {
    for (j = 1; j <= known; j++)
      if (titled(title[j], order[i])) {
        print "open issue #" number[j] ": " title[j]
        issue[order[i]] = issue[order[i]] "\nopen issue #" number[j] ": " title[j]
      }
    if (issues != "" && !(order[i] in issue)) print "no open issue names " order[i]
  }
  for (i = 1; i <= notes; i++) print "::error " where[i] "::" escape(text[i] issue[test[i]], 0)
}' "$work/summary"

exit "$ran"
