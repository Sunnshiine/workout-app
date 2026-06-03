#!/usr/bin/env bash
#
# ralph.sh — autonomous "Ralph Wiggum" remediation loop for the WorkoutTracker iOS app.
#
# Each iteration runs a FRESH agent context that:
#   1. selects the highest-priority unblocked `ready-for-agent` GitHub issue (skipping PRDs),
#   2. resolves whether the issue ships to main or an existing PR branch,
#   3. implements it with TDD in an isolated git worktree,
#   4. hands the result to a fresh Swift-review phase,
#   5. hands the reviewed result to a fresh UI-verification phase,
#   6. is gated on the full documented framework before shipping,
#   7. on success: merges the branch to the resolved target, pushes, and closes the issue;
#      on failure: relabels the issue `ready-for-human` and moves on.
# The loop stops when no eligible issues remain, or after MAX_ITER iterations.
#
# Works with either Claude Code or Codex:   --engine claude | codex
#
# Usage:
#   ralph/ralph.sh [--engine claude|codex] [--max-iterations N] [--no-push] [--select-only]
#                  [--model NAME] [--device "iPhone 17 Pro"] [--codex-sandbox]
#                  [--implement-timeout-seconds N] [--publish-target auto|main|branch]
#                  [--target-branch BRANCH] [--target-pr N]
#
# WARNING: with defaults this PUSHES to the resolved target and CLOSES issues unattended.
#          Pass --no-push to keep commits local while you build trust.
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
PUBLISH_TARGET="${PUBLISH_TARGET:-auto}"
TARGET_BRANCH="${TARGET_BRANCH:-}"
TARGET_PR="${TARGET_PR:-}"

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
    --publish-target|--ship-target) PUBLISH_TARGET="$2"; shift 2;;
    --target-branch|--pr-branch) TARGET_BRANCH="$2"; shift 2;;
    --target-pr) TARGET_PR="$2"; shift 2;;
    -h|--help) sed -n '2,28p' "$0"; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

case "$ENGINE" in claude|codex) ;; *) echo "engine must be 'claude' or 'codex'" >&2; exit 2;; esac
case "$PUBLISH_TARGET" in auto|main|branch) ;; *) echo "publish target must be 'auto', 'main', or 'branch'" >&2; exit 2;; esac

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

  for source in "$REPO_ROOT/Secrets.xcconfig"; do
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

issue_branch_directive() {
  local issue="$1"
  gh issue view "$issue" --json body --jq .body 2>/dev/null \
    | sed -n '/Target branch:/,/^$/p' \
    | sed -n 's/.*`\([^`][^`]*\)`.*/\1/p' \
    | head -1
}

issue_pr_directive() {
  local issue="$1"
  gh issue view "$issue" --json body --jq .body 2>/dev/null \
    | grep -Eo 'https://github.com/[^[:space:]]+/pull/[0-9]+' \
    | head -1 \
    | sed 's#.*/pull/##'
}

resolve_issue_publish_target() {
  local issue="$1" branch_directive pr_directive
  branch_directive="$(issue_branch_directive "$issue")"
  pr_directive="$(issue_pr_directive "$issue")"

  ISSUE_TARGET_BRANCH="$TARGET_BRANCH"
  ISSUE_TARGET_PR="$TARGET_PR"

  if [ -z "$ISSUE_TARGET_BRANCH" ]; then
    ISSUE_TARGET_BRANCH="$branch_directive"
  fi
  if [ -z "$ISSUE_TARGET_PR" ]; then
    ISSUE_TARGET_PR="$pr_directive"
  fi

  case "$PUBLISH_TARGET" in
    main)
      ISSUE_PUBLISH_TARGET="main"
      ISSUE_TARGET_BRANCH=""
      ;;
    branch)
      ISSUE_PUBLISH_TARGET="branch"
      ;;
    auto)
      if [ -n "$ISSUE_TARGET_BRANCH" ]; then
        ISSUE_PUBLISH_TARGET="branch"
      else
        ISSUE_PUBLISH_TARGET="main"
      fi
      ;;
  esac

  if [ "$ISSUE_PUBLISH_TARGET" = branch ] && [ -z "$ISSUE_TARGET_BRANCH" ]; then
    return 1
  fi
  return 0
}

resolve_publish_base_ref() {
  if [ "${ISSUE_PUBLISH_TARGET:-main}" = main ]; then
    printf '%s\n' main
    return 0
  fi

  git -C "$REPO_ROOT" fetch origin "$ISSUE_TARGET_BRANCH" >/dev/null 2>&1 || true
  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/remotes/origin/$ISSUE_TARGET_BRANCH"; then
    printf 'origin/%s\n' "$ISSUE_TARGET_BRANCH"
    return 0
  fi
  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$ISSUE_TARGET_BRANCH"; then
    printf '%s\n' "$ISSUE_TARGET_BRANCH"
    return 0
  fi
  return 1
}

publish_description() {
  if [ "${ISSUE_PUBLISH_TARGET:-main}" = branch ]; then
    printf 'existing PR branch `%s`' "$ISSUE_TARGET_BRANCH"
  else
    printf '`main`'
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

phase_complete_line() {
  printf '<promise phase="%s">COMPLETE</promise>\n' "$1"
}

phase_blocked_reason() {
  local phase="$1" out="$2"
  printf '%s\n' "$out" | awk -v phase="$phase" '
    {
      start = "<promise phase=\"" phase "\">BLOCKED:"
      p = index($0, start)
      if (p == 0) next
      reason = substr($0, p + length(start))
      q = index(reason, "</promise>")
      if (q > 0) reason = substr(reason, 1, q - 1)
      sub(/^[[:space:]]+/, "", reason)
      print reason
      exit
    }'
}

production_swift_changed() {
  local wt="$1" base="$2" tip="$3"
  git -C "$wt" diff --name-only "$base" "$tip" -- \
    'WorkoutTracker/*.swift' \
    ':(glob)WorkoutTracker/**/*.swift' \
    'Package.swift' \
    'project.yml' \
    'WorkoutTracker.xcodeproj/project.pbxproj' | grep -q .
}

run_issue_phase() {
  local phase="$1" prompt_file="$2" iter="$3" issue="$4" wt="$5" branch="$6" issue_base="$7"
  local complete_line blocked_prefix phase_prompt phase_log phase_status phase_out reason

  complete_line="$(phase_complete_line "$phase")"
  blocked_prefix="<promise phase=\"$phase\">BLOCKED:"
  phase_prompt="Engine: $ENGINE. This is the $phase phase.
You are working GitHub issue #$issue.
You are inside an isolated git worktree at: $wt   (branch: $branch).
ISSUE_BASE_REF: $issue_base
PUBLISH_TARGET: $ISSUE_PUBLISH_TARGET
TARGET_BRANCH: ${ISSUE_TARGET_BRANCH:-main}
TARGET_PR: ${ISSUE_TARGET_PR:-}
PHASE_NAME: $phase
COMPLETE_PROMISE_LINE: $complete_line
BLOCKED_PROMISE_PREFIX: $blocked_prefix
UI_SHOT_PATH (relative to the worktree root): ralph/.artifacts/issue-$issue-ui-review.png
UI_REVIEW_PATH (relative to the worktree root): ralph/.artifacts/issue-$issue-ui-review.md
OBSERVATIONS_LOG_PATH (absolute; the persistent main-repo log to tail for recurrence, read-only): $OBS

Ralph resolved this issue's publication target before creating your worktree. If
PUBLISH_TARGET is branch, the issue ships back to TARGET_BRANCH and must not
open a replacement PR, push main, merge main, or close TARGET_PR. If
PUBLISH_TARGET is main, the issue ships through Ralph's normal direct-to-main
gate.

Gate handoff is strict: Ralph advances only when your final output contains the exact
COMPLETE_PROMISE_LINE above. Words like done, completed, success, or the old
<promise>COMPLETE</promise> marker do not count and will fail this phase.

$(cat "$PROMPTS/$prompt_file")"
  phase_log="$LOGS/iter-$iter-issue-$issue-$phase.log"
  note "issue #$issue $phase started — timeout ${IMPLEMENT_TIMEOUT_SECONDS}s"
  run_agent_to_file_with_timeout "$phase_prompt" "$wt" "$IMPLEMENT_TIMEOUT_SECONDS" "$phase_log"
  phase_status=$?
  phase_out="$(cat "$phase_log" 2>/dev/null || true)"

  if [ "$phase_status" -eq 124 ]; then
    harvest_observations "$iter" "$issue" "$phase BLOCKED" "$phase_out"
    flag_for_human "$issue" "$phase timed out after ${IMPLEMENT_TIMEOUT_SECONDS}s without reporting completion."
    return 1
  fi

  if printf '%s\n' "$phase_out" | grep -Fxq "$complete_line"; then
    harvest_observations "$iter" "$issue" "$phase COMPLETE" "$phase_out"
    note "issue #$issue $phase complete"
    return 0
  fi

  harvest_observations "$iter" "$issue" "$phase BLOCKED" "$phase_out"
  reason="$(phase_blocked_reason "$phase" "$phase_out")"
  flag_for_human "$issue" "${reason:-$phase did not report the exact completion promise. Expected: $complete_line}"
  return 1
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
    log "View change detected → checking UI phase screenshot review"
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
log "Ralph loop starting — engine=$ENGINE max-iter=$MAX_ITER push=$PUSH publish-target=$PUBLISH_TARGET device='$SIM_DEVICE'"
[ -f "$ACTIVITY" ] || printf "# Ralph Activity Log\n\n" > "$ACTIVITY"
[ -f "$OBS" ] || printf "# Ralph Observations\n\n> Append-only, gitignored. Read-only signal harvested from IMPLEMENT iterations — never auto-applied to docs. Consolidate manually when an entry flags the file as large.\n\n" > "$OBS"
note "run start — engine=$ENGINE max-iter=$MAX_ITER push=$PUSH publish-target=$PUBLISH_TARGET"

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

  if ! resolve_issue_publish_target "$issue"; then
    flag_for_human "$issue" "Publish target is branch, but no target branch was configured or found in the issue body."
    continue
  fi
  log "issue #$issue publish target: $(publish_description)"
  note "issue #$issue publish target: $(publish_description)"

  if [ "$SELECT_ONLY" = 1 ]; then
    log "select-only mode — stopping before worktree creation."
    note "select-only selected issue #$issue"
    break
  fi

  issue_base_ref="$(resolve_publish_base_ref)"
  if [ -z "$issue_base_ref" ]; then
    flag_for_human "$issue" "Could not resolve publish base ref for $(publish_description)."
    continue
  fi

  # 2. ISOLATE — fresh worktree + branch off the resolved publish target
  branch="agent/issue-$issue"
  wt="$REPO_ROOT/.claude/worktrees/issue-$issue"
  git -C "$REPO_ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || true
  git -C "$REPO_ROOT" branch -D "$branch" >/dev/null 2>&1 || true
  git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1 || true
  if ! git -C "$REPO_ROOT" worktree add -b "$branch" "$wt" "$issue_base_ref" >/dev/null 2>&1; then
    flag_for_human "$issue" "Could not create the worktree/branch."; continue
  fi
  if ! copy_secrets_xcconfig "$wt"; then
    git -C "$REPO_ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || true
    git -C "$REPO_ROOT" branch -D "$branch" >/dev/null 2>&1 || true
    git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1 || true
    flag_for_human "$issue" "Could not copy Secrets.xcconfig into the issue worktree."; continue
  fi
  issue_base="$(git -C "$wt" rev-parse HEAD)"

  # 3. IMPLEMENT (TDD) inside the worktree. No UI tests or review subagents here.
  if ! run_issue_phase "implement-tdd" "implement.md" "$iter" "$issue" "$wt" "$branch" "$issue_base"; then
    continue
  fi

  # 4. SWIFT REVIEW — fresh context, reviewer subagent, non-UI remediation only.
  if ! run_issue_phase "swift-review" "swift-review.md" "$iter" "$issue" "$wt" "$branch" "$issue_base"; then
    continue
  fi

  # 5. UI VERIFY — fresh context owns UI tests, screenshots, and UI screenshot review.
  ui_phase_base="$(git -C "$wt" rev-parse HEAD)"
  if ! run_issue_phase "ui-verify" "ui-verify.md" "$iter" "$issue" "$wt" "$branch" "$issue_base"; then
    continue
  fi
  ui_phase_tip="$(git -C "$wt" rev-parse HEAD)"

  # If UI verification changed production Swift/project files, review that new code
  # before the loop accepts the issue implementation.
  if production_swift_changed "$wt" "$ui_phase_base" "$ui_phase_tip"; then
    log "UI verification changed production Swift/project files → running fresh Swift re-review"
    note "issue #$issue swift-review-after-ui required"
    if ! run_issue_phase "swift-review-after-ui" "swift-review.md" "$iter" "$issue" "$wt" "$branch" "$issue_base"; then
      continue
    fi
  fi

  issue_tip="$(git -C "$wt" rev-parse HEAD)"

  # 6. UI ARTIFACT GATE — compare only this issue's own implementation range.
  if ! check_ui_artifacts "$issue" "$iter" "$wt" "$issue_base" "$issue_tip"; then
    continue
  fi

  # 7. INTEGRATE — merge into a temporary worktree, then gate the exact tree to be shipped.
  integration_branch="agent/issue-$issue-integration"
  integration_wt="$REPO_ROOT/.claude/worktrees/issue-$issue-integration"
  cleanup_integration_worktree "$integration_wt" "$integration_branch"
  integration_base_ref="$(resolve_publish_base_ref)"
  if [ -z "$integration_base_ref" ]; then
    flag_for_human "$issue" "Could not resolve current publish base ref for $(publish_description)." gate; continue
  fi
  if ! git -C "$REPO_ROOT" worktree add -b "$integration_branch" "$integration_wt" "$integration_base_ref" >/dev/null 2>&1; then
    flag_for_human "$issue" "Could not create the integration worktree/branch."; continue
  fi
  if ! copy_secrets_xcconfig "$integration_wt"; then
    cleanup_integration_worktree "$integration_wt" "$integration_branch"
    flag_for_human "$issue" "Could not copy Secrets.xcconfig into the integration worktree." gate; continue
  fi

  log "merging #$issue into integration worktree for $(publish_description)"
  if ! git -C "$integration_wt" merge --no-ff --no-commit "$branch" >/dev/null 2>&1; then
    cleanup_integration_worktree "$integration_wt" "$integration_branch"
    flag_for_human "$issue" "Merge into current publish target ($(publish_description)) conflicted." gate; continue
  fi

  # 8. GATE — authoritative full testing framework on the integrated tree.
  if ! run_full_gate "$issue" "$iter" "$integration_wt"; then
    cleanup_integration_worktree "$integration_wt" "$integration_branch"
    continue
  fi

  # 9. SHIP — commit the already-gated merge, fast-forward/push the target, close
  if ! git -C "$integration_wt" commit -m "merge: resolve #$issue via Ralph ($ENGINE)" >/dev/null 2>&1; then
    cleanup_integration_worktree "$integration_wt" "$integration_branch"
    flag_for_human "$issue" "Could not create the integrated merge commit."; continue
  fi

  if [ "$ISSUE_PUBLISH_TARGET" = branch ]; then
    if [ "$PUSH" = 1 ]; then
      if git -C "$integration_wt" push origin "HEAD:$ISSUE_TARGET_BRANCH" >/dev/null 2>&1; then
        log "pushed origin/$ISSUE_TARGET_BRANCH"
      else
        flag_for_human "$issue" "Could not push gated merge commit to origin/$ISSUE_TARGET_BRANCH; integration worktree left at $integration_wt." gate
        git -C "$REPO_ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || true
        git -C "$REPO_ROOT" branch -d "$branch" >/dev/null 2>&1 || git -C "$REPO_ROOT" branch -D "$branch" >/dev/null 2>&1 || true
        continue
      fi
    else
      log "no-push branch mode — gated commit left at $integration_wt on $integration_branch; issue left open."
      note "issue #$issue gated for origin/$ISSUE_TARGET_BRANCH but not pushed because --no-push was set"
      git -C "$REPO_ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || true
      git -C "$REPO_ROOT" branch -d "$branch" >/dev/null 2>&1 || git -C "$REPO_ROOT" branch -D "$branch" >/dev/null 2>&1 || true
      break
    fi
    gh issue close "$issue" --comment "> *Resolved autonomously by the Ralph loop ($ENGINE).*

Pushed to \`origin/$ISSUE_TARGET_BRANCH\`. PR ${ISSUE_TARGET_PR:+#$ISSUE_TARGET_PR }remains open for review/merge." >/dev/null 2>&1 || true
  else
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
  fi

  # 10. CLEANUP
  cleanup_integration_worktree "$integration_wt" "$integration_branch"
  git -C "$REPO_ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || true
  git -C "$REPO_ROOT" branch -d "$branch" >/dev/null 2>&1 || git -C "$REPO_ROOT" branch -D "$branch" >/dev/null 2>&1 || true
  if [ "$ISSUE_PUBLISH_TARGET" = branch ]; then
    note "issue #$issue resolved & pushed to origin/$ISSUE_TARGET_BRANCH"
  else
    note "issue #$issue resolved & merged to main$( [ "$PUSH" = 1 ] && echo ', pushed' )"
  fi
  log "issue #$issue DONE"
done

log "Ralph loop finished."
note "run end"
