#!/usr/bin/env bash
set -uo pipefail

# shellcheck source=scripts/tests/ci-wait-harness.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ci-wait-harness.sh"

echo "the landing check: it runs against the fetched base and gates the merge command"

check "a green PR runs the landing check against the fetched base, with the PR body" 0 "$ci_a_success
$merge" 668 "[$(ci $A completed success)]"
if grep -qx "git fetch -q --no-tags origin +refs/heads/main:refs/remotes/origin/main $sha" "$root/case/calls.log" \
    && grep -q "^landing-check origin/main $sha --body-file .* body=Reverts #12$" "$root/case/calls.log"; then
    ok "the landing check reads origin/main after a fetch, the head, and the PR body"
else
    bad "the landing check reads origin/main after a fetch, the head, and the PR body: $(grep -E '^(git|landing)' "$root/case/calls.log")"
fi

landing_status=1 landing_out="revert: the landing undoes #1066 620/627 lines (3ee0d077 feat(ci): flake guard)" \
    check "a landing that undoes a commit on the base exits 1 with no merge command" 1 "$ci_a_success
revert: the landing undoes #1066 620/627 lines (3ee0d077 feat(ci): flake guard)" 668 "[$(ci $A completed success)]"
check_err "a landing that undoes a commit says why there is no merge command" \
    "the landing of #668 onto main fails scripts/landing-reverts-main.py, so there is no merge command"

fetch_error="fatal: unable to access github.com" check "a failed fetch of the base exits 1 with no merge command" 1 "$ci_a_success" 668 \
    "[$(ci $A completed success)]"
check_err "a failed fetch says what it could not fetch" "fatal: unable to access github.com
could not fetch main and 73b27aa for the landing check"

landing_status=2 check "a landing the check cannot read exits 1 with no merge command" 1 "$ci_a_success" 668 \
    "[$(ci $A completed success)]"

check "a red run never reaches the landing check" 1 "CI failure on 73b27aa (run $A)
  swift-tests: failure
  lint: failure
  visual-tests: failure" 668 "[$(ci $A completed failure)]"
if grep -q '^landing-check' "$root/case/calls.log"; then bad "a red run never reaches the landing check"; else ok "a red run calls no landing check"; fi

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
