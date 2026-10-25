#!/usr/bin/env bash
set -uo pipefail

# shellcheck source=scripts/tests/ci-wait-harness.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ci-wait-harness.sh"

echo "green: exit 0 and the pinned merge command"

check "a run that succeeds" 0 "$ci_a_success
$merge" 668 \
    "[$(ci $A in_progress "")]" \
    "[$(ci $A completed success)]"

check "a run that appears after two polls" 0 "$ci_a_success
$merge" 668 \
    "[]" "[]" \
    "[$(ci $A in_progress "")]" \
    "[$(ci $A completed success)]"

check "#680: a same-second duplicate's newer run decides over the cancelled one" 0 "$ci_b_success
$merge" 668 \
    "[$(ci $A completed cancelled), $(ci $B in_progress "")]" \
    "[$(ci $A completed cancelled), $(ci $B completed success)]"

check "#680: the duplicate cancels the run the first poll found" 0 "$ci_b_success
$merge" 668 \
    "[$(ci $A in_progress "")]" \
    "[$(ci $B queued ""), $(ci $A completed cancelled)]" \
    "[$(ci $B completed success), $(ci $A completed cancelled)]"

check "PR 668 live: each workflow's cancelled duplicate loses to its newer run" 0 "$ci_b_success
Verify tools success on 73b27aa (run $W)
  sheet: success
  tree: success
$merge" 668 \
    "[$(ci $B completed success), $(workflow_run "Verify tools" $V completed cancelled sheet tree), $(workflow_run "Verify tools" $W completed success sheet tree), $(ci $A completed cancelled)]"

check "a newer run that passes after the watched run failed decides" 0 "$ci_b_success
$merge" 668 \
    "[$(ci $A in_progress "")]" \
    "[$(ci $B in_progress ""), $(ci $A completed failure)]" \
    "[$(ci $B completed success), $(ci $A completed failure)]"

check "a run waiting on environment approval is waited on" 0 "$ci_a_success
$merge" 668 \
    "[$(ci $A waiting "")]" \
    "[$(ci $A completed success)]"

check "#796: a PR whose only workflow is not CI and passes succeeds" 0 "Workflow lint success on 73b27aa (run $L)
  skill-links: success
$merge" 668 \
    "[$(workflow_run "Workflow lint" $L in_progress "" skill-links)]" \
    "[$(workflow_run "Workflow lint" $L completed success skill-links)]"

check "a skipped run, and a run from another event on the head, are not read" 0 "$ci_a_success
$merge" 668 \
    "[$(workflow_run "TestFlight PR" $C completed skipped archive upload), $(jq -c '.event = "issues"' <<<"$(workflow_run "Agent Review" $B completed failure review)"), $(ci $A completed success)]"

branch_tips="$pushed $pushed $pushed" check "#694: a head pushed seconds ago is waited on, not the previous head's green run" 0 "CI success on f2c0ffe (run $C)
  swift-tests: success
  lint: success
  visual-tests: success
gh pr merge 668 --squash --match-head-commit $pushed" 668 \
    "[$(ci $A completed success)]" \
    "[$(on_pushed "$(ci $C in_progress "")"), $(ci $A completed success)]" \
    "[$(on_pushed "$(ci $C completed success)"), $(ci $A completed success)]"

echo "red or unfinished: never exit 0"

check "a run that fails" 1 "CI failure on 73b27aa (run $A)
  swift-tests: failure
  lint: failure
  visual-tests: failure" 668 \
    "[$(ci $A in_progress "")]" \
    "[$(ci $A completed failure)]"

check "#796: a red check from another workflow fails a PR that CI skipped" 1 "Workflow lint failure on 73b27aa (run $L)
  skill-links: failure" 795 \
    "[$(workflow_run "Workflow lint" $L completed failure skill-links)]"

check "#796: a red check from another workflow fails a PR whose CI is green" 1 "$ci_a_success
Workflow lint failure on 73b27aa (run $L)
  skill-links: failure" 795 \
    "[$(workflow_run "Workflow lint" $L completed failure skill-links), $(ci $A completed success)]"

check "a workflow still running after CI finished decides" 1 "$ci_a_success
Verify tools failure on 73b27aa (run $W)
  sheet: failure
  tree: failure" 668 \
    "[$(ci $A in_progress ""), $(workflow_run "Verify tools" $W in_progress "" sheet tree)]" \
    "[$(ci $A completed success), $(workflow_run "Verify tools" $W in_progress "" sheet tree)]" \
    "[$(ci $A completed success), $(workflow_run "Verify tools" $W completed failure sheet tree)]"

check "a queued run cancelled by hand fails" 1 "CI cancelled on 73b27aa (run $A)
  swift-tests: cancelled
  lint: cancelled
  visual-tests: cancelled" 668 \
    "[$(ci $A queued "")]" \
    "[$(ci $A completed cancelled)]"

check "an older green run does not rescue a cancelled newest run" 1 "CI cancelled on 73b27aa (run $B)
  swift-tests: cancelled
  lint: cancelled
  visual-tests: cancelled" 668 \
    "[$(ci $B completed cancelled), $(ci $A completed success)]"

check "a failed build is not erased by a later skipped run" 1 "TestFlight PR failure on 73b27aa (run $B)
  build: failure" 668 \
    "[$(workflow_run "TestFlight PR" $C completed skipped build), $(workflow_run "TestFlight PR" $B completed failure build)]"

check "a build cancelled before it finished fails though a later run skipped" 1 "$ci_a_success
TestFlight PR cancelled on 73b27aa (run $B)
  build: cancelled" 668 \
    "[$(workflow_run "TestFlight PR" $C completed skipped build), $(workflow_run "TestFlight PR" $B completed cancelled build), $(ci $A completed success)]"

check "a run that needs approval to start fails" 1 "CI action_required on 73b27aa (run $A)
  swift-tests: action_required
  lint: action_required
  visual-tests: action_required" 668 \
    "[$(ci $A completed action_required)]"

check "a workflow that failed to start fails" 1 "$ci_a_success
Workflow lint startup_failure on 73b27aa (run $L)" 668 \
    "[$(ci $A completed success), $(jq -c '.jobs = []' <<<"$(workflow_run "Workflow lint" $L completed startup_failure)")]"

echo "late runs: never answer from an earlier event's finished runs"

check "a workflow created after a finished one is waited on" 1 "CI failure on 73b27aa (run $A)
  swift-tests: failure
  lint: failure
  visual-tests: failure
Workflow lint success on 73b27aa (run $L)
  skill-links: success" 668 \
    "[]" \
    "[$(workflow_run "Workflow lint" $L completed success skill-links)]" \
    "[$(workflow_run "Workflow lint" $L completed success skill-links), $(ci $A in_progress "")]" \
    "[$(workflow_run "Workflow lint" $L completed success skill-links), $(ci $A completed failure)]"

check "a re-trigger on a green head waits for its new run" 1 "CI failure on 73b27aa (run $B)
  swift-tests: failure
  lint: failure
  visual-tests: failure" 668 \
    "[$(ci $A completed success)]" \
    "[$(ci $B queued ""), $(ci $A completed success)]" \
    "[$(ci $B completed failure), $(ci $A completed success)]"

check "a testflight label applied just before the wait is waited on" 1 "$ci_a_success
TestFlight PR failure on 73b27aa (run $C)
  archive: failure
  upload: failure" 668 \
    "[$(ci $A completed success)]" \
    "[$(workflow_run "TestFlight PR" $C queued "" archive upload), $(ci $A completed success)]" \
    "[$(workflow_run "TestFlight PR" $C completed failure archive upload), $(ci $A completed success)]"

branch_tips="$pushed $pushed $pushed" check "a force-push back to a tested commit waits for its new run" 1 "CI failure on f2c0ffe (run $B)
  swift-tests: failure
  lint: failure
  visual-tests: failure" 668 \
    "[$(on_pushed "$(ci $A completed success)")]" \
    "[$(on_pushed "$(ci $B queued "")"), $(on_pushed "$(ci $A completed success)")]" \
    "[$(on_pushed "$(ci $B completed failure)"), $(on_pushed "$(ci $A completed success)")]"

echo "head moved: never vouch for a head it did not watch"

branch_tips="$sha $pushed $pushed" check "a push that cancels nothing on the watched head, onto a red head, fails" 1 "" 668 \
    "[$(ci $A completed success), $(workflow_run "TestFlight PR" $B in_progress "" archive upload)]" \
    "[$(on_pushed "$(ci $C in_progress "")"), $(ci $A completed success), $(workflow_run "TestFlight PR" $B in_progress "" archive upload)]" \
    "[$(on_pushed "$(ci $C completed failure)"), $(ci $A completed success), $(workflow_run "TestFlight PR" $B completed success archive upload)]"
check_err "a moved head names both commits" "the head of #668 moved from 73b27aa to f2c0ffe during the wait; run ci-wait.sh 668 again"

branch_tips="$sha $pushed" check "a push that cancels the watched run fails" 1 "" 668 \
    "[$(ci $A in_progress "")]" \
    "[$(on_pushed "$(ci $B in_progress "")"), $(ci $A completed cancelled)]"

branch_tips="$sha $sha $pushed" check "a push during a wait that found no run fails instead of exiting 3" 1 "" 668 \
    "[]" "[]" "[$(on_pushed "$(ci $B in_progress "")")]"

echo "base changed: never vouch for a run against the earlier base"

base_changed=2026-10-12T11:00:00Z check "a green run created before the base changed fails" 1 "CI ran on 73b27aa against a base other than #668's main (run $A)" 668 \
    "[$(ci $A completed success)]"
check_err "a run against the earlier base says how to rerun it" "push to topic, an empty commit if nothing changed, so every workflow runs against main"

base_changed=2026-10-12T11:00:00Z check "the run a base change starts is waited on and decides" 0 "$ci_b_success
$merge" 668 \
    "[$(ci $A completed success)]" \
    "[$(after_base_change "$(ci $B queued "")"), $(ci $A completed success)]" \
    "[$(after_base_change "$(ci $B completed success)"), $(ci $A completed success)]"

base_changed=2026-10-12T11:00:00Z check "a workflow that did not rerun after the base changed fails a PR whose CI reran green" 1 "$ci_b_success
Verify tools ran on 73b27aa against a base other than #668's main (run $W)" 668 \
    "[$(after_base_change "$(ci $B completed success)"), $(ci $A completed success), $(workflow_run "Verify tools" $W completed success sheet tree)]"

base=ui/10-move-on-ceremony check "#857 live: another PR's run on the head, against main, does not vouch for a PR based on ui/10" 1 "CI ran on 73b27aa against a base other than #668's ui/10-move-on-ceremony (run $A)" 668 \
    "[$(from_probe_pr main "$(ci $A completed success)")]"

base_changed=2026-10-12T11:00:00Z check "a probe PR's run against main vouches for a PR retargeted to main after it" 0 "$ci_a_success
$merge" 668 \
    "[$(from_probe_pr main "$(ci $A completed success)")]"

graphql_error="HTTP 502: Bad Gateway (https://api.github.com/graphql)" check "a failed base lookup exits 1 with no merge command" 1 "" 668 \
    "[$(ci $A completed success)]"

echo "no run: exit 3"

check "a PR that starts no run exits 3 and prints no merge command" 3 "" 668 "[]"
check_err "a PR that starts no run names the commit and what to check before landing" "no pull_request workflow ran on 73b27aa within 5 minutes
land #668 only when every path it changes is in ci.yml's paths-ignore and no agent workflow pushed 73b27aa (#805)"

check "a PR whose only runs were skipped exits 3" 3 "" 668 \
    "[$(workflow_run "TestFlight PR" $A completed skipped build), $(workflow_run "Verify tools" $W completed skipped sheet)]"

echo "arguments"

for arg in "" main fix/retro-ciwait 999b783; do
    check "'$arg' is not a PR number and exits 2" 2 "" "$arg" "[$(ci $A completed success)]"
done

fork=true check "a PR from a fork exits 1, though this repo has a branch of the same name" 1 "" 668 \
    "[$(ci $A completed success)]"
check_err "a PR from a fork says the script does not handle it" "#668 comes from a fork, and ci-wait.sh does not handle fork PRs"

pr_error="HTTP 502: Bad Gateway (https://api.github.com/graphql)" check "a gh pr view failure exits 1" 1 "" 668 \
    "[$(ci $A completed success)]"
check_err "a gh pr view failure prints gh's error" "HTTP 502: Bad Gateway (https://api.github.com/graphql)"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
