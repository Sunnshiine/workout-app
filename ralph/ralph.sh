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

while [ $# -gt 0 ]; do
  case "$1" in
    --engine) ENGINE="$2"; shift 2;;
    --max-iterations|--max-iter) MAX_ITER="$2"; shift 2;;
    --no-push) PUSH=0; shift;;
    --select-only) SELECT_ONLY=1; shift;;
    --model) MODEL="$2"; shift 2;;
    --device) SIM_DEVICE="$2"; shift 2;;
    --codex-sandbox) CODEX_BYPASS=0; shift;;
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
mkdir -p "$LOGS"
export SIM_DEVICE

ts()   { date "+%Y-%m-%d %H:%M:%S"; }
log()  { echo "[$(ts)] $*"; }
note() { printf -- "- **%s** — %s\n" "$(ts)" "$*" >> "$ACTIVITY"; }

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

flag_for_human() {
  local issue="$1" reason="$2"
  gh issue edit "$issue" --add-label "$HUMAN_LABEL" --remove-label "$LABEL" >/dev/null 2>&1 || true
  gh issue comment "$issue" --body "> *Ralph loop ($ENGINE) could not complete this autonomously.*

$reason" >/dev/null 2>&1 || true
  note "issue #$issue → $HUMAN_LABEL: $reason"
  log  "issue #$issue flagged for human: $reason"
}

# ---- main loop -----------------------------------------------------------
log "Ralph loop starting — engine=$ENGINE max-iter=$MAX_ITER push=$PUSH device='$SIM_DEVICE'"
[ -f "$ACTIVITY" ] || printf "# Ralph Activity Log\n\n" > "$ACTIVITY"
note "run start — engine=$ENGINE max-iter=$MAX_ITER push=$PUSH"

if [ "$SELECT_ONLY" != 1 ] && [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
  log "working tree is dirty; refusing to run mutating phases."
  note "run stopped — dirty working tree"
  exit 1
fi

for (( iter=1; iter<=MAX_ITER; iter++ )); do
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

  # 3+4. IMPLEMENT (TDD) inside the worktree
  impl_prompt="Engine: $ENGINE. This is the IMPLEMENT phase.
You are working GitHub issue #$issue.
You are inside an isolated git worktree at: $wt   (branch: $branch).

$(cat "$PROMPTS/implement.md")"
  impl_out="$(run_agent "$impl_prompt" "$wt")"
  echo "$impl_out" > "$LOGS/iter-$iter-issue-$issue-implement.log"

  if ! printf '%s' "$impl_out" | grep -q '<promise>COMPLETE</promise>'; then
    reason="$(printf '%s' "$impl_out" | grep -oE '<promise>BLOCKED:.*</promise>' | head -1 | sed 's/<[^>]*>//g')"
    flag_for_human "$issue" "${reason:-Agent did not report completion.}"; continue
  fi

  # 5. GATE — authoritative full testing framework in the worktree
  log "gate: swift test (package unit/component)"
  if ! ( cd "$wt" && swift test ) > "$LOGS/iter-$iter-issue-$issue-swift-test.log" 2>&1; then
    flag_for_human "$issue" "Package unit/component tests failed at the loop gate: swift test (see logs)."; continue
  fi
  log "gate: xcodegen generate"
  if ! ( cd "$wt" && xcodegen generate ) > "$LOGS/iter-$iter-issue-$issue-xcodegen.log" 2>&1; then
    flag_for_human "$issue" "Project generation failed at the loop gate: xcodegen generate (see logs)."; continue
  fi
  log "gate: xcodebuild test (unit/component target)"
  if ! ( cd "$wt" && \
         xcodebuild -project WorkoutTracker.xcodeproj -scheme WorkoutTracker -configuration Debug \
           -destination "platform=iOS Simulator,name=$SIM_DEVICE" -derivedDataPath "$wt/.ralph-dd" \
           test -only-testing:WorkoutTrackerTests ) \
         > "$LOGS/iter-$iter-issue-$issue-xcode-unit-component-tests.log" 2>&1; then
    flag_for_human "$issue" "Xcode unit/component tests failed at the loop gate: WorkoutTrackerTests (see logs)."; continue
  fi
  log "gate: xcodebuild test (UI integration target)"
  if ! ( cd "$wt" && \
         xcodebuild -project WorkoutTracker.xcodeproj -scheme WorkoutTracker -configuration Debug \
           -destination "platform=iOS Simulator,name=$SIM_DEVICE" -derivedDataPath "$wt/.ralph-dd" \
           test -only-testing:WorkoutTrackerUITests ) \
         > "$LOGS/iter-$iter-issue-$issue-xcode-ui-tests.log" 2>&1; then
    flag_for_human "$issue" "UI integration tests failed at the loop gate: WorkoutTrackerUITests (see logs)."; continue
  fi
  log "gate: swiftlint lint"
  if ! ( cd "$wt" && swiftlint lint --quiet ) > "$LOGS/iter-$iter-issue-$issue-swiftlint.log" 2>&1; then
    flag_for_human "$issue" "Lint failed at the loop gate: swiftlint lint --quiet (see logs)."; continue
  fi

  # 5b. UI ARTIFACT GATE — screenshot review is implementer-owned for View/Theme changes
  if git -C "$wt" diff --name-only main -- 'WorkoutTracker/Views/' 'WorkoutTracker/Theme.swift' | grep -q .; then
    log "View change detected → checking implementer-owned UI screenshot review"
    ui_shot_rel="ralph/.artifacts/issue-$issue-ui-review.png"
    ui_review_rel="ralph/.artifacts/issue-$issue-ui-review.md"
    ui_shot="$wt/$ui_shot_rel"
    ui_review="$wt/$ui_review_rel"
    if [ ! -s "$ui_shot" ]; then
      flag_for_human "$issue" "View/Theme changes require a non-empty UI screenshot artifact: $ui_shot_rel."; continue
    fi
    if [ ! -s "$ui_review" ]; then
      flag_for_human "$issue" "View/Theme changes require a saved UI Screenshot Review artifact: $ui_review_rel."; continue
    fi
    if ! tail -n 1 "$ui_review" | grep -Fxq "PASS: no blocking static visual findings."; then
      flag_for_human "$issue" "UI Screenshot Review did not end with PASS. Review artifact: $ui_review_rel."; continue
    fi
    cp "$ui_shot" "$ART/iter-$iter-issue-$issue.png"
    cp "$ui_review" "$ART/iter-$iter-issue-$issue-ui-review.md"
  fi

  # 6. SHIP — merge to main, push, close
  log "merging #$issue into main"
  if ! git -C "$REPO_ROOT" merge --no-ff "$branch" -m "merge: resolve #$issue via Ralph ($ENGINE)" >/dev/null 2>&1; then
    git -C "$REPO_ROOT" merge --abort >/dev/null 2>&1 || true
    flag_for_human "$issue" "Merge into main conflicted."; continue
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

  # 7. CLEANUP
  git -C "$REPO_ROOT" worktree remove --force "$wt" >/dev/null 2>&1 || true
  git -C "$REPO_ROOT" branch -d "$branch" >/dev/null 2>&1 || git -C "$REPO_ROOT" branch -D "$branch" >/dev/null 2>&1 || true
  note "issue #$issue resolved & merged to main$( [ "$PUSH" = 1 ] && echo ', pushed' )"
  log "issue #$issue DONE"
done

log "Ralph loop finished."
note "run end"
