#!/usr/bin/env bash
#
# ralph.sh — autonomous "Ralph Wiggum" remediation loop for the WorkoutTracker iOS app.
#
# Each iteration runs a FRESH agent context that:
#   1. selects the highest-priority unblocked `ready-for-agent` GitHub issue (skipping PRDs),
#   2. works it to completion in an isolated git worktree using TDD,
#   3. is gated on the full documented framework: `swift test`, Xcode unit/component tests,
#      Xcode UI integration tests, and `swiftlint lint --quiet`; View/Theme changes are screenshot
#      reviewed by an implementer-owned subagent before completion,
#   4. on success: merges the branch to main, pushes origin, and closes the issue;
#      on failure: relabels the issue `ready-for-human` and moves on.
# The loop stops when no eligible issues remain, or after MAX_ITER iterations.
#
# Works with either Claude Code or Codex:   --engine claude | codex
#
# Usage:
#   ralph/ralph.sh [--engine claude|codex] [--max-iterations N] [--no-push] [--select-only]
#                  [--model NAME] [--device "iPhone 17 Pro"] [--codex-sandbox]
#                  [--implement-timeout-seconds N]
#
# WARNING: with defaults this PUSHES to origin/main and CLOSES issues unattended.
#          Pass --no-push to keep commits local (issues are still closed on the remote).
#
set -uo pipefail

# ---- config / args -------------------------------------------------------
ENGINE="${ENGINE:-claude}"
MAX_ITER="${MAX_ITER:-5}"
PUSH="${PUSH:-1}"
SELECT_ONLY="${SELECT_ONLY:-0}"
MODEL="${MODEL:-}"
CODEX_BYPASS="${CODEX_BYPASS:-1}"
LABEL="${LABEL:-ready-for-agent}"
HUMAN_LABEL="${HUMAN_LABEL:-ready-for-human}"
SIM_DEVICE="${SIM_DEVICE:-iPhone 17 Pro}"
IMPLEMENT_TIMEOUT_SECONDS="${IMPLEMENT_TIMEOUT_SECONDS:-2700}"

while [ $# -gt 0 ]; do
  case "$1" in
    --engine) ENGINE="$2"; shift 2;;
    --max-iterations|--max-iter) MAX_ITER="$2"; shift 2;;
    --no-push) PUSH=0; shift;;
    --select-only) SELECT_ONLY=1; shift;;
    --model) MODEL="$2"; shift 2;;
    --device) SIM_DEVICE="$2"; shift 2;;
    --codex-sandbox) CODEX_BYPASS=0; shift;;
    --implement-timeout-seconds) IMPLEMENT_TIMEOUT_SECONDS="$2"; shift 2;;
    -h|--help) sed -n '2,28p' "$0"; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

case "$ENGINE" in claude|codex) ;; *) echo "engine must be 'claude' or 'codex'" >&2; exit 2;; esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
PROMPTS="$SCRIPT_DIR/prompts"
ART="$SCRIPT_DIR/.artifacts"
LOGS="$ART/logs"
ACTIVITY="$ART/activity.md"
OBS="$ART/observations.md"
mkdir -p "$LOGS"
export SIM_DEVICE

ts()   { date "+%Y-%m-%d %H:%M:%S"; }
log()  { echo "[$(ts)] $*"; }
note() { printf -- "- **%s** — %s\n" "$(ts)" "$*" >> "$ACTIVITY"; }

secrets_xcconfig_source() {
  local source
  if [ -n "${SECRETS_XCCONFIG_SOURCE:-}" ]; then
    if [ -f "$SECRETS_XCCONFIG_SOURCE" ]; then
      printf '%s\n' "$SECRETS_XCCONFIG_SOURCE"
      return 0
    fi
    return 2
  fi

  for source in "$REPO_ROOT/Secrets.xcconfig" "/Users/sunny/Projects/workout-app/Secrets.xcconfig"; do
    if [ -n "$source" ] && [ -f "$source" ]; then
      printf '%s\n' "$source"
      return 0
    fi
  done
  return 1
}

copy_secrets_xcconfig() {
  local destination="$1" source
  source="$(secrets_xcconfig_source)"
  case "$?" in
    0) ;;
    1) return 0 ;;
    *)
      log "SECRETS_XCCONFIG_SOURCE is set but does not point to a file: $SECRETS_XCCONFIG_SOURCE"
      return 1
      ;;
  esac
  if ! cp "$source" "$destination/Secrets.xcconfig"; then
    log "failed to copy Secrets.xcconfig from $source to $destination"
    return 1
  fi
}

# ---- engine abstraction --------------------------------------------------
# run_agent <prompt-text> <workdir> [image]  ->  prints the agent's final message to stdout
run_agent() {
  local prompt="$1" workdir="$2" image="${3:-}"
  if [ "$ENGINE" = codex ]; then
    local last trace
    last="$(mktemp)"
    trace="$(mktemp)"
    local -a a=(exec --skip-git-repo-check -C "$workdir" -o "$last")
    if [ "$CODEX_BYPASS" = 1 ]; then
      a+=(--dangerously-bypass-approvals-and-sandbox --dangerously-bypass-hook-trust)
    else
      a+=(--sandbox workspace-write)
    fi
    [ -n "$MODEL" ] && a+=(-m "$MODEL")
    [ -n "$image" ] && a+=(-i "$image" --)
    codex "${a[@]}" "$prompt" > "$trace" 2>&1 || true
    if [ -s "$last" ]; then
      cat "$last" 2>/dev/null
    else
      cat "$trace" 2>/dev/null
    fi
    rm -f "$last" "$trace"
  else
    local m="${MODEL:-opus}"
    ( cd "$workdir" && claude -p "$prompt" \
        --permission-mode bypassPermissions --model "$m" --add-dir "$REPO_ROOT" 2>/dev/null ) || true
  fi
}

run_agent_to_file_with_timeout() {
  local prompt="$1" workdir="$2" timeout_seconds="$3" outfile="$4"
  local pid started_at elapsed status

  ( run_agent "$prompt" "$workdir" > "$outfile" ) &
  pid=$!
  started_at="$(date +%s)"

  while kill -0 "$pid" >/dev/null 2>&1; do
    elapsed=$(( $(date +%s) - started_at ))
    if [ "$elapsed" -ge "$timeout_seconds" ]; then
      pkill -TERM -P "$pid" >/dev/null 2>&1 || true
      kill -TERM "$pid" >/dev/null 2>&1 || true
      sleep 2
      pkill -KILL -P "$pid" >/dev/null 2>&1 || true
      kill -KILL "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
      return 124
    fi
    sleep 10
  done

  wait "$pid"
  status=$?
  return "$status"
}

flag_for_human() {
  local issue="$1" reason="$2" kind="${3:-}"
  gh issue edit "$issue" --add-label "$HUMAN_LABEL" --remove-label "$LABEL" >/dev/null 2>&1 || true
  gh issue comment "$issue" --body "> *Ralph loop ($ENGINE) could not complete this autonomously.*

$reason" >/dev/null 2>&1 || true
  note "issue #$issue → $HUMAN_LABEL: $reason"
  log  "issue #$issue flagged for human: $reason"
  # Gate failures happen after the agent context is gone; record the loop's own
  # factual one-liner so "which gate fails most" is visible in the observations log.
  if [ "$kind" = gate ]; then
    {
      printf '## %s · iter %s · #%s · GATE-FAIL\n' "$(ts)" "${CURRENT_ITER:-?}" "$issue"
      printf -- '[friction] %s\n\n' "$reason"
    } >> "$OBS"
  fi
}

# Harvest the agent's <observations>…</observations> block from its captured output and
# append it under a loop-written header. Writes nothing when the block is absent or NONE.
harvest_observations() {
  local iter="$1" issue="$2" outcome="$3" out="$4" body trimmed
  body="$(printf '%s\n' "$out" | awk '
    {
      s = $0
      if (!inside) {
        p = index(s, "<observations>")
        if (p == 0) next
        inside = 1
        s = substr(s, p + 14)            # 14 = length("<observations>")
      }
      q = index(s, "</observations>")
      if (q > 0) { s = substr(s, 1, q - 1); if (s != "") print s; exit }
      if (s != "") print s
    }')"
  trimmed="$(printf '%s' "$body" | tr -d '[:space:]')"
  if [ -z "$trimmed" ] || [ "$trimmed" = "NONE" ]; then return 0; fi
  {
    printf '## %s · iter %s · #%s · %s\n' "$(ts)" "$iter" "$issue" "$outcome"
    printf '%s\n\n' "$body"
  } >> "$OBS"
}

run_full_gate() {
  local issue="$1" iter="$2" gate_wt="$3"

  log "gate: swift test (package unit/component)"
  if ! ( cd "$gate_wt" && swift test ) > "$LOGS/iter-$iter-issue-$issue-swift-test.log" 2>&1; then
    flag_for_human "$issue" "Package unit/component tests failed at the loop gate: swift test (see logs)." gate
    return 1
  fi
  log "gate: xcodegen generate"
  if ! ( cd "$gate_wt" && xcodegen generate ) > "$LOGS/iter-$iter-issue-$issue-xcodegen.log" 2>&1; then
    flag_for_human "$issue" "Project generation failed at the loop gate: xcodegen generate (see logs)." gate
    return 1
  fi
  log "gate: xcodebuild test (unit/component target)"
  if ! ( cd "$gate_wt" && \
         xcodebuild -project WorkoutTracker.xcodeproj -scheme WorkoutTracker -configuration Debug \
           -destination "platform=iOS Simulator,name=$SIM_DEVICE" -derivedDataPath "$gate_wt/.ralph-dd" \
           test -only-testing:WorkoutTrackerTests ) \
         > "$LOGS/iter-$iter-issue-$issue-xcode-unit-component-tests.log" 2>&1; then
    flag_for_human "$issue" "Xcode unit/component tests failed at the loop gate: WorkoutTrackerTests (see logs)." gate
    return 1
  fi
  log "gate: xcodebuild test (UI integration target)"
  if ! ( cd "$gate_wt" && \
         xcodebuild -project WorkoutTracker.xcodeproj -scheme WorkoutTracker -configuration Debug \
           -destination "platform=iOS Simulator,name=$SIM_DEVICE" -derivedDataPath "$gate_wt/.ralph-dd" \
           test -only-testing:WorkoutTrackerUITests ) \
         > "$LOGS/iter-$iter-issue-$issue-xcode-ui-tests.log" 2>&1; then
    flag_for_human "$issue" "UI integration tests failed at the loop gate: WorkoutTrackerUITests (see logs)." gate
    return 1
  fi
  log "gate: swiftlint lint"
  if ! ( cd "$gate_wt" && swiftlint lint --quiet ) > "$LOGS/iter-$iter-issue-$issue-swiftlint.log" 2>&1; then
    flag_for_human "$issue" "Lint failed at the loop gate: swiftlint lint --quiet (see logs)." gate
    return 1
  fi
  return 0
}

check_ui_artifacts() {
  local issue="$1" iter="$2" wt="$3" issue_base="$4" issue_tip="$5"
  local ui_shot_rel ui_review_rel ui_shot ui_review

  if git -C "$wt" diff --name-only "$issue_base" "$issue_tip" -- \
      'WorkoutTracker/Views/' 'WorkoutTracker/Theme.swift' | grep -q .; then
    log "View change detected → checking implementer-owned UI screenshot review"
    ui_shot_rel="ralph/.artifacts/issue-$issue-ui-review.png"
    ui_review_rel="ralph/.artifacts/issue-$issue-ui-review.md"
    ui_shot="$wt/$ui_shot_rel"
    ui_review="$wt/$ui_review_rel"
    if [ ! -s "$ui_shot" ]; then
      flag_for_human "$issue" "View/Theme changes require a non-empty UI screenshot artifact: $ui_shot_rel." gate
      return 1
    fi
    if [ ! -s "$ui_review" ]; then
      flag_for_human "$issue" "View/Theme changes require a saved UI Screenshot Review artifact: $ui_review_rel." gate
      return 1
    fi
    if ! tail -n 1 "$ui_review" | grep -Fxq "PASS: no blocking static visual findings."; then
      flag_for_human "$issue" "UI Screenshot Review did not end with PASS. Review artifact: $ui_review_rel." gate
      return 1
    fi
    cp "$ui_shot" "$ART/iter-$iter-issue-$issue.png"
    cp "$ui_review" "$ART/iter-$iter-issue-$issue-ui-review.md"
  fi
  return 0
}

cleanup_integration_worktree() {
  local integration_wt="$1" integration_branch="$2"

  git -C "$integration_wt" merge --abort >/dev/null 2>&1 || true
  git -C "$REPO_ROOT" worktree remove --force "$integration_wt" >/dev/null 2>&1 || true
  git -C "$REPO_ROOT" branch -D "$integration_branch" >/dev/null 2>&1 || true
  git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1 || true
}

# ---- main loop -----------------------------------------------------------
log "Ralph loop starting — engine=$ENGINE max-iter=$MAX_ITER push=$PUSH device='$SIM_DEVICE'"
[ -f "$ACTIVITY" ] || printf "# Ralph Activity Log\n\n" > "$ACTIVITY"
[ -f "$OBS" ] || printf "# Ralph Observations\n\n> Append-only, gitignored. Read-only signal harvested from IMPLEMENT iterations — never auto-applied to docs. Consolidate manually when an entry flags the file as large.\n\n" > "$OBS"
note "run start — engine=$ENGINE max-iter=$MAX_ITER push=$PUSH"

if [ "$SELECT_ONLY" != 1 ] && [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
  log "working tree is dirty; refusing to run mutating phases."
  note "run stopped — dirty working tree"
  exit 1
fi

for (( iter=1; iter<=MAX_ITER; iter++ )); do
  CURRENT_ITER="$iter"
  log "──────── iteration $iter/$MAX_ITER ────────"

  # 1. SELECT (read-only, in the main checkout)
  sel_prompt="Engine: $ENGINE. This is the SELECT phase.

$(cat "$PROMPTS/select.md")"
  sel_out="$(run_agent "$sel_prompt" "$REPO_ROOT")"
  echo "$sel_out" > "$LOGS/iter-$iter-select.log"
  issue="$(printf '%s\n' "$sel_out" | grep -oE 'SELECTED_ISSUE=(NONE|[0-9]+)' | tail -1 | cut -d= -f2)"

  if [ -z "$issue" ]; then
    log "selector returned no parseable result — stopping."; note "selector returned no result — stopping"; break
  fi
  if [ "$issue" = NONE ]; then
    log "no eligible ready-for-agent issues — done."; note "no eligible issues — loop complete"; break
  fi
  log "selected issue #$issue"; note "iteration $iter: selected issue #$issue"

  if [ "$SELECT_ONLY" = 1 ]; then
    log "select-only mode — stopping before worktree creation."
    note "select-only selected issue #$issue"
    break
  fi

  # 2. ISOLATE — fresh worktree + branch off main
  branch="agent/issue-$issue"
  wt="$REPO_ROOT/.claude/worktrees/issue-$issue"
  git -C "$REPO_ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || true
  git -C "$REPO_ROOT" branch -D "$branch" >/dev/null 2>&1 || true
  git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1 || true
  if ! git -C "$REPO_ROOT" worktree add -b "$branch" "$wt" main >/dev/null 2>&1; then
    flag_for_human "$issue" "Could not create the worktree/branch."; continue
  fi
  if ! copy_secrets_xcconfig "$wt"; then
    git -C "$REPO_ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || true
    git -C "$REPO_ROOT" branch -D "$branch" >/dev/null 2>&1 || true
    git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1 || true
    flag_for_human "$issue" "Could not copy Secrets.xcconfig into the issue worktree."; continue
  fi
  issue_base="$(git -C "$wt" rev-parse HEAD)"

  # 3+4. IMPLEMENT (TDD) inside the worktree
  impl_prompt="Engine: $ENGINE. This is the IMPLEMENT phase.
You are working GitHub issue #$issue.
You are inside an isolated git worktree at: $wt   (branch: $branch).
ISSUE_BASE_REF: $issue_base
UI_SHOT_PATH (relative to the worktree root): ralph/.artifacts/issue-$issue-ui-review.png
UI_REVIEW_PATH (relative to the worktree root): ralph/.artifacts/issue-$issue-ui-review.md
OBSERVATIONS_LOG_PATH (absolute; the persistent main-repo log to tail for recurrence, read-only): $OBS

$(cat "$PROMPTS/implement.md")"
  impl_log="$LOGS/iter-$iter-issue-$issue-implement.log"
  note "issue #$issue implement started — timeout ${IMPLEMENT_TIMEOUT_SECONDS}s"
  run_agent_to_file_with_timeout "$impl_prompt" "$wt" "$IMPLEMENT_TIMEOUT_SECONDS" "$impl_log"
  impl_status=$?
  impl_out="$(cat "$impl_log" 2>/dev/null || true)"
  if [ "$impl_status" -eq 124 ]; then
    harvest_observations "$iter" "$issue" "BLOCKED" "$impl_out"
    flag_for_human "$issue" "IMPLEMENT timed out after ${IMPLEMENT_TIMEOUT_SECONDS}s without reporting completion."
    continue
  fi

  if printf '%s' "$impl_out" | grep -q '<promise>COMPLETE</promise>'; then
    harvest_observations "$iter" "$issue" "COMPLETE" "$impl_out"
  else
    harvest_observations "$iter" "$issue" "BLOCKED" "$impl_out"
    reason="$(printf '%s' "$impl_out" | grep -oE '<promise>BLOCKED:.*</promise>' | head -1 | sed 's/<[^>]*>//g')"
    flag_for_human "$issue" "${reason:-Agent did not report completion.}"; continue
  fi
  issue_tip="$(git -C "$wt" rev-parse HEAD)"

  # 5. UI ARTIFACT GATE — compare only this issue's own implementation range.
  if ! check_ui_artifacts "$issue" "$iter" "$wt" "$issue_base" "$issue_tip"; then
    continue
  fi

  # 6. INTEGRATE — merge into a temporary worktree, then gate the exact tree to be shipped.
  integration_branch="agent/issue-$issue-integration"
  integration_wt="$REPO_ROOT/.claude/worktrees/issue-$issue-integration"
  cleanup_integration_worktree "$integration_wt" "$integration_branch"
  if ! git -C "$REPO_ROOT" worktree add -b "$integration_branch" "$integration_wt" main >/dev/null 2>&1; then
    flag_for_human "$issue" "Could not create the integration worktree/branch."; continue
  fi
  if ! copy_secrets_xcconfig "$integration_wt"; then
    cleanup_integration_worktree "$integration_wt" "$integration_branch"
    flag_for_human "$issue" "Could not copy Secrets.xcconfig into the integration worktree." gate; continue
  fi

  log "merging #$issue into integration worktree"
  if ! git -C "$integration_wt" merge --no-ff --no-commit "$branch" >/dev/null 2>&1; then
    cleanup_integration_worktree "$integration_wt" "$integration_branch"
    flag_for_human "$issue" "Merge into current main conflicted." gate; continue
  fi

  # 7. GATE — authoritative full testing framework on the integrated tree.
  if ! run_full_gate "$issue" "$iter" "$integration_wt"; then
    cleanup_integration_worktree "$integration_wt" "$integration_branch"
    continue
  fi

  # 8. SHIP — commit the already-gated merge, fast-forward main, push, close
  if ! git -C "$integration_wt" commit -m "merge: resolve #$issue via Ralph ($ENGINE)" >/dev/null 2>&1; then
    cleanup_integration_worktree "$integration_wt" "$integration_branch"
    flag_for_human "$issue" "Could not create the integrated merge commit."; continue
  fi
  if ! git -C "$REPO_ROOT" merge --ff-only "$integration_branch" >/dev/null 2>&1; then
    cleanup_integration_worktree "$integration_wt" "$integration_branch"
    flag_for_human "$issue" "Could not fast-forward main to the gated integration branch."; continue
  fi
  if [ "$PUSH" = 1 ]; then
    if git -C "$REPO_ROOT" push origin main >/dev/null 2>&1; then
      log "pushed origin/main"
    else
      log "WARN: push to origin failed (the merge is on local main)."; note "issue #$issue: push to origin failed"
    fi
  fi
  gh issue close "$issue" --comment "> *Resolved autonomously by the Ralph loop ($ENGINE).*

Merged to \`main\`." >/dev/null 2>&1 || true

  # 9. CLEANUP
  cleanup_integration_worktree "$integration_wt" "$integration_branch"
  git -C "$REPO_ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || true
  git -C "$REPO_ROOT" branch -d "$branch" >/dev/null 2>&1 || git -C "$REPO_ROOT" branch -D "$branch" >/dev/null 2>&1 || true
  note "issue #$issue resolved & merged to main$( [ "$PUSH" = 1 ] && echo ', pushed' )"
  log "issue #$issue DONE"
done

log "Ralph loop finished."
note "run end"
