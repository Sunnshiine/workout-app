#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ci_wait="$script_dir/../ci-wait.sh"
[ -x "$ci_wait" ] || { echo "not executable: $ci_wait" >&2; exit 2; }

root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/bin"
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

sha=73b27aad97eff49511b45cf10e614f1d6b72e46b

cat >"$root/bin/next-frame" <<'STUB'
#!/usr/bin/env bash
next=$(( $(cat "$STUB_DIR/cursor") + 1 ))
[ -f "$STUB_DIR/frames/$next.json" ] && echo "$next" >"$STUB_DIR/cursor"
exit 0
STUB
cat >"$root/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[ "$(wc -l <"$STUB_DIR/calls.log")" -lt 200 ] || { echo "gh stub: 200 calls, ci-wait.sh is looping" >&2; exit 99; }
printf '%s\n' "$*" >>"$STUB_DIR/calls.log"
frame="$STUB_DIR/frames/$(cat "$STUB_DIR/cursor").json"
sub="$1 $2"
shift 2
id="" jq_expr="." limit=20 commit="" workflow=""
while [ $# -gt 0 ]; do
    case "$1" in
        --jq) jq_expr=$2; shift 2 ;;
        --limit) limit=$2; shift 2 ;;
        --commit) commit=$2; shift 2 ;;
        --workflow) workflow=$2; shift 2 ;;
        --json | --interval) shift 2 ;;
        -*) echo "gh stub: unexpected flag $1" >&2; exit 1 ;;
        *) id=$1; shift ;;
    esac
done
case "$sub" in
    "pr view") jq -nr --arg s "$STUB_SHA" '{headRefOid: $s}' | jq -r "$jq_expr" ;;
    "api repos/{owner}/{repo}/commits/"*) jq -nr --arg s "$STUB_SHA" '{sha: $s}' | jq -r "$jq_expr" ;;
    "run list")
        [ "$workflow" = CI ] || { echo "gh stub: workflow $workflow" >&2; exit 1; }
        if [ "$commit" = "$STUB_SHA" ]; then jq ".[:$limit]" "$frame"; else echo '[]'; fi | jq -r "$jq_expr" ;;
    "run watch") next-frame ;;
    "run view")
        jq -e --argjson id "$id" '.[] | select(.databaseId == $id)' "$frame" >"$STUB_DIR/view.json" \
            || { echo "gh stub: no run $id" >&2; exit 1; }
        jq -r "$jq_expr" "$STUB_DIR/view.json" ;;
    *) echo "gh stub: unexpected command: $sub $*" >&2; exit 1 ;;
esac
STUB
cat >"$root/bin/sleep" <<'STUB'
#!/usr/bin/env bash
exec next-frame
STUB
chmod +x "$root/bin/next-frame" "$root/bin/gh" "$root/bin/sleep"

run_record() {
    local id=$1 status=$2 conclusion=$3
    shift 3
    [ $# -gt 0 ] || set -- swift-tests lint visual-tests
    jq -nc --argjson id "$id" --arg s "$status" --arg c "$conclusion" \
        '{databaseId: $id, status: $s, conclusion: $c,
          jobs: [$ARGS.positional[] | {name: ., conclusion: $c}]}' --args "$@"
}

check() {
    local name=$1 want_status=$2 want_out=$3 arg=$4
    shift 4
    local dir="$root/case"
    rm -rf "$dir"
    mkdir -p "$dir/frames"
    local i=0
    for f in "$@"; do printf '%s\n' "$f" >"$dir/frames/$i.json"; i=$((i + 1)); done
    echo 0 >"$dir/cursor"
    : >"$dir/calls.log"
    STUB_DIR="$dir" STUB_SHA="$sha" PATH="$root/bin:$PATH" "$ci_wait" "$arg" >"$dir/out" 2>"$dir/err"
    local status=$?
    if [ "$status" -eq "$want_status" ] && [ "$(cat "$dir/out")" = "$want_out" ]; then
        ok "$name"
    else
        bad "$name"
        printf 'want exit %s, stdout:\n%s\n' "$want_status" "$want_out" | sed 's/^/       /'
        printf 'got exit %s, stdout:\n%s\n' "$status" "$(cat "$dir/out")" | sed 's/^/       /'
        [ -s "$dir/err" ] && sed 's/^/       stderr: /' "$dir/err"
        sed 's/^/       gh /' "$dir/calls.log"
    fi
}

# Frames list runs in the API's order: newest createdAt first, lower id first on a tie.
A=35742049156
B=35742049318
C=35742049999

success_b="CI success on 73b27aa (run $B)
  visual-tests: success
  swift-tests: success
  lint: success"

check "#680 live order: same-second duplicates list the cancelled run first" 0 "$success_b" 668 \
    "[$(run_record $A completed cancelled), $(run_record $B in_progress "" visual-tests swift-tests lint)]" \
    "[$(run_record $A completed cancelled), $(run_record $B completed success visual-tests swift-tests lint)]"

check "#680 race: the duplicate cancels the run the first poll found" 0 "$success_b" 668 \
    "[$(run_record $A in_progress "")]" \
    "[$(run_record $B in_progress "" visual-tests swift-tests lint), $(run_record $A completed cancelled)]" \
    "[$(run_record $B completed success visual-tests swift-tests lint), $(run_record $A completed cancelled)]"

check "a second retarget cancels the run that replaced the first" 0 "CI success on 73b27aa (run $C)
  swift-tests: success
  lint: success
  visual-tests: success" 668 \
    "[$(run_record $A in_progress "")]" \
    "[$(run_record $B in_progress ""), $(run_record $A completed cancelled)]" \
    "[$(run_record $C in_progress ""), $(run_record $B completed cancelled), $(run_record $A completed cancelled)]" \
    "[$(run_record $C completed success), $(run_record $B completed cancelled), $(run_record $A completed cancelled)]"

check "the run that replaced a cancelled one fails" 1 "CI failure on 73b27aa (run $B)
  swift-tests: failure
  lint: failure
  visual-tests: failure" 668 \
    "[$(run_record $A in_progress "")]" \
    "[$(run_record $B in_progress ""), $(run_record $A completed cancelled)]" \
    "[$(run_record $B completed failure), $(run_record $A completed cancelled)]"

check "a newer run that starts after the watched run failed decides" 0 "CI success on 73b27aa (run $B)
  swift-tests: success
  lint: success
  visual-tests: success" 668 \
    "[$(run_record $A in_progress "")]" \
    "[$(run_record $B in_progress ""), $(run_record $A completed failure)]" \
    "[$(run_record $B completed success), $(run_record $A completed failure)]"

check "an older green run does not rescue a cancelled newest run" 1 "CI cancelled on 73b27aa (run $B)
  swift-tests: cancelled
  lint: cancelled
  visual-tests: cancelled" 668 \
    "[$(run_record $B completed cancelled), $(run_record $A completed success)]"

check "a cancelled run with no newer run on the commit reports cancelled" 1 "CI cancelled on 73b27aa (run $A)
  swift-tests: cancelled
  lint: cancelled
  visual-tests: cancelled" 668 \
    "[$(run_record $A in_progress "")]" \
    "[$(run_record $A completed cancelled)]"

check "a single run that succeeds" 0 "CI success on 73b27aa (run $A)
  swift-tests: success
  lint: success
  visual-tests: success" 668 \
    "[$(run_record $A in_progress "")]" \
    "[$(run_record $A completed success)]"

check "a single run that fails" 1 "CI failure on 73b27aa (run $A)
  swift-tests: failure
  lint: failure
  visual-tests: failure" 668 \
    "[$(run_record $A in_progress "")]" \
    "[$(run_record $A completed failure)]"

check "a run that appears after two polls" 0 "CI success on 73b27aa (run $A)
  swift-tests: success
  lint: success
  visual-tests: success" main \
    "[]" "[]" \
    "[$(run_record $A in_progress "")]" \
    "[$(run_record $A completed success)]"

check "a commit that never gets a run exits 3" 3 "" 668 "[]"
if grep -qx "no CI run for 73b27aa after 5 minutes; ci.yml paths-ignore skips docs-only changes" "$root/case/err"; then
    ok "a commit that never gets a run names the paths-ignore cause"
else
    bad "a commit that never gets a run: stderr was $(cat "$root/case/err")"
fi

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
