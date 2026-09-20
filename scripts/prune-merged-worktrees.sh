#!/usr/bin/env bash
# Remove git worktrees whose pull request has merged or closed, together with
# their local branches. Dry run by default; --apply is the only thing that
# deletes.
#
# The repo squash-merges, so `git branch --merged` never matches a landed
# branch. Every branch is resolved through its PR state instead, in one batched
# `gh` call per run.
#
# Usage: prune-merged-worktrees.sh [--apply] [--repo <path>] [--no-size]
set -uo pipefail

apply=no
repo=""
want_size=yes

usage() {
    cat <<'USAGE'
prune-merged-worktrees.sh [--apply] [--repo <path>] [--no-size]

Lists every git worktree whose PR has merged or closed and which holds no work
that removal would lose. Prints the plan and exits without changing anything.

  --apply        remove the listed worktrees and delete their local branches
  --repo <path>  operate on this repository (default: the repo containing $PWD)
  --no-size      skip the du pass, which dominates the runtime on large trees

Size is logical size per worktree, so content shared between worktrees by a
hardlink or an APFS clone is counted once in each.

A worktree is removed only when every one of these holds:
  it is not the primary checkout and not the one this script runs from
  it is on a branch (a detached HEAD is always kept)
  it has no uncommitted changes and no untracked files
  its branch has a pull request, and that PR is MERGED or CLOSED
  it has no commits the PR never received

An unresolvable fact keeps the worktree. Nothing unknown is ever removed.
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --apply) apply=yes ;;
        --no-size) want_size=no ;;
        --repo) shift; repo="${1:-}"; [ -z "$repo" ] && { echo "--repo needs a path" >&2; exit 2; } ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

# cd alone does not stop these from redirecting every git call, including the
# two that delete. This script is run by agents from inside worktrees, which is
# exactly where they leak.
unset GIT_DIR GIT_WORK_TREE

if [ -z "$repo" ]; then
    repo=$(git rev-parse --show-toplevel 2>/dev/null)
fi
[ -z "$repo" ] && { echo "not in a git repository; pass --repo <path>" >&2; exit 2; }
cd "$repo" || exit 2

# The primary checkout holds .git as a real directory; every linked worktree
# points into it. Deriving it this way does not depend on list ordering.
primary=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
self=$(git rev-parse --show-toplevel 2>/dev/null)

# GNU and BSD spell epoch-to-date differently; pick once.
if date -u -d @0 +%Y-%m-%d >/dev/null 2>&1; then
    ymd() { date -u -d "@$1" +%Y-%m-%d; }
else
    ymd() { date -u -r "$1" +%Y-%m-%d; }
fi

work=$(mktemp -d) || exit 3
trap 'rm -rf "$work"' EXIT
prmap="$work/prmap.tsv"
rows="$work/rows.tsv"
: >"$prmap"
: >"$rows"

# One batched call. 178 PRs in this repo fit well inside the limit, and a
# per-branch lookup would be one request per worktree. No cache: a stale entry
# could report a reopened PR as merged, and that error deletes.
pr_lookup_note="one batched gh pr list call"
if ! command -v gh >/dev/null 2>&1; then
    echo "warn: gh not found; every worktree will be kept for want of a PR state" >&2
    pr_lookup_note="gh unavailable"
elif ! command -v jq >/dev/null 2>&1; then
    echo "warn: jq not found; every worktree will be kept for want of a PR state" >&2
    pr_lookup_note="jq unavailable"
else
    pr_limit=1000
    if pr_json=$(gh pr list --state all --limit "$pr_limit" \
            --json number,state,headRefName,headRefOid 2>"$work/gh.err"); then
        # One row per branch. A branch name can carry several PRs here, seven
        # do today, so the choice is made rather than left to gh's ordering: an
        # OPEN PR wins because open always means keep, and otherwise the
        # highest number wins as the most recent. Picking a stale MERGED row
        # over a live OPEN one would remove a worktree someone is using, and
        # the head-OID check cannot catch it while the upstream ref resolves.
        printf '%s' "$pr_json" \
            | jq -r 'group_by(.headRefName)
                     | map((map(select(.state == "OPEN")) | first)
                           // (sort_by(.number) | last))
                     | .[] | [.headRefName, .number, .state, .headRefOid] | @tsv' >"$prmap"
        pr_count=$(wc -l <"$prmap" | tr -d ' ')
        pr_lookup_note="one batched gh pr list call, $pr_count branches with a PR"
        if [ "$pr_count" -ge "$pr_limit" ]; then
            echo "warn: gh returned $pr_count PRs at the limit of $pr_limit; older branches may be missing and will be kept" >&2
        fi
    else
        echo "warn: gh pr list failed; every worktree will be kept: $(cat "$work/gh.err")" >&2
        pr_lookup_note="gh pr list failed"
    fi
fi

pr_field() {
    awk -F '\t' -v b="$1" -v n="$2" '$1 == b { print $n; exit }' "$prmap"
}

# Emit NUL-delimited path/branch/head/prunable quadruples. A blank record
# terminates each worktree in the porcelain stream.
parse_worktrees() {
    local field="" wt="" branch="" head="" prunable=no
    while IFS= read -r -d '' field; do
        if [ -z "$field" ]; then
            [ -n "$wt" ] && printf '%s\0%s\0%s\0%s\0' "$wt" "$branch" "$head" "$prunable"
            wt=""; branch=""; head=""; prunable=no
        elif [ "${field#worktree }" != "$field" ]; then wt="${field#worktree }"
        elif [ "${field#branch refs/heads/}" != "$field" ]; then branch="${field#branch refs/heads/}"
        elif [ "${field#HEAD }" != "$field" ]; then head="${field#HEAD }"
        elif [ "${field#prunable}" != "$field" ]; then prunable=yes
        fi
    done < <(git worktree list --porcelain -z)
    [ -n "$wt" ] && printf '%s\0%s\0%s\0%s\0' "$wt" "$branch" "$head" "$prunable"
}

# Answers "does this worktree hold commits the PR never received". An upstream
# that still resolves answers it directly. When it does not, the branch is
# either gone (the repo deletes merged branches) or was never tracked, and both
# are answered by the SHA GitHub recorded on the PR, never by assuming nothing
# is lost.
compute_remote() {
    # compute_remote <worktree> <pr head oid>
    local wt="$1" pr_oid="$2" upstream ahead head
    head=$(git -C "$wt" rev-parse HEAD 2>/dev/null) || { echo unknown; return; }
    if upstream=$(git -C "$wt" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) \
       && git -C "$wt" rev-parse --verify --quiet "$upstream" >/dev/null 2>&1; then
        ahead=$(git -C "$wt" rev-list --count "$upstream..HEAD" 2>/dev/null)
        case "$ahead" in
            ''|*[!0-9]*) echo unknown ;;
            0) echo pushed ;;
            *) echo "ahead:$ahead" ;;
        esac
    elif [ -n "$pr_oid" ] && [ "$pr_oid" = "$head" ]; then
        echo "gone=pr-head"
    elif [ -n "$pr_oid" ] && git -C "$wt" cat-file -e "$pr_oid" 2>/dev/null \
         && git -C "$wt" merge-base --is-ancestor HEAD "$pr_oid" 2>/dev/null; then
        echo "gone=in-pr-head"
    elif [ -n "$pr_oid" ]; then
        echo "gone=ahead-of-pr-head"
    else
        echo no-upstream
    fi
}

# The only three states that prove removal would lose nothing. Anything else,
# including every state added here later, keeps the worktree.
remote_is_safe() {
    case "$1" in pushed|gone=pr-head|gone=in-pr-head) return 0 ;; *) return 1 ;; esac
}

worktree_is_clean() {
    local porcelain
    porcelain=$(git -C "$1" status --porcelain 2>/dev/null) || return 1
    [ -z "$porcelain" ]
}

now=$(date +%s)

while IFS= read -r -d '' wt && IFS= read -r -d '' branch \
   && IFS= read -r -d '' head && IFS= read -r -d '' prunable; do

    pr_num="-"; pr_state="-"; pr_oid=""
    dirty="-"; remote="-"; size="-"; touched="-"
    verdict=keep; reason=""

    if [ "$wt" = "$primary" ]; then
        reason="primary checkout"
    elif [ "$wt" = "$self" ]; then
        reason="this script is running from it"
    elif [ "$prunable" = yes ]; then
        reason="worktree directory is gone; pruning administrative files is not this script's job"
    fi

    if [ -z "$reason" ]; then
        if [ "$want_size" = yes ] && s=$(du -sh "$wt" 2>/dev/null); then
            size=$(printf '%s\n' "$s" | awk '{print $1}')
        fi
        # The commit date, not a file mtime. An index mtime moves when git
        # merely reads the tree, including this script's own status call below.
        if head_ts=$(git -C "$wt" log -1 --format=%ct HEAD 2>/dev/null) \
           && [ -n "$head_ts" ]; then
            touched="$(ymd "$head_ts") ($(( (now - head_ts) / 86400 ))d)"
        fi

        if porcelain=$(git -C "$wt" status --porcelain 2>/dev/null); then
            tracked=$(printf '%s\n' "$porcelain" | grep -cv '^??' || true)
            untracked=$(printf '%s\n' "$porcelain" | grep -c '^??' || true)
            if [ -z "$porcelain" ]; then dirty=clean
            elif [ "$tracked" -gt 0 ]; then dirty="modified:$tracked"
            else dirty="untracked:$untracked"
            fi
        else
            dirty=unknown
        fi

        if [ -z "$branch" ]; then
            remote=detached
        else
            pr_num=$(pr_field "$branch" 2)
            pr_state=$(pr_field "$branch" 3)
            pr_oid=$(pr_field "$branch" 4)
            [ -z "$pr_num" ] && { pr_num="-"; pr_state="none"; }

            remote=$(compute_remote "$wt" "$pr_oid")
        fi

        # Ordered decision table. First match wins, and every rule that cannot
        # establish a fact resolves to keep.
        if [ "$remote" = detached ]; then
            reason="detached HEAD: no branch resolves to a PR, and no ref would survive removal"
        elif [ "$dirty" = unknown ]; then
            reason="could not read the working tree status"
        elif [ "$dirty" != clean ]; then
            reason="uncommitted changes ($dirty)"
        elif [ "$pr_state" = none ]; then
            reason="no pull request for $branch"
        elif [ "$pr_state" = "-" ]; then
            reason="PR state unavailable"
        elif [ "$pr_state" = OPEN ]; then
            reason="PR #$pr_num is open"
        elif ! remote_is_safe "$remote"; then
            # Must stay above the MERGED/CLOSED rule. A merged PR says the
            # branch landed, not that this worktree holds nothing newer.
            reason="commits the PR never received ($remote)"
        elif [ "$pr_state" = MERGED ] || [ "$pr_state" = CLOSED ]; then
            verdict=remove
            reason="PR #$pr_num $pr_state"
        else
            reason="unrecognised PR state $pr_state"
        fi
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$verdict" "${branch:--}" "$pr_num" "$pr_state" "$size" "$touched" \
        "$remote" "${dirty:--}" "$reason" "$wt" "$head" "$pr_oid" >>"$rows"
done < <(parse_worktrees)

align() { awk -F '\t' '{ for (i=1;i<=NF;i++) { c[NR,i]=$i; if (length($i)>w[i]) w[i]=length($i) } n=NF>n?NF:n }
    END { for (r=1;r<=NR;r++) { line=""; for (i=1;i<=n;i++) { v=c[r,i]; line=line sprintf("%-*s  ", w[i], v) } sub(/ +$/,"",line); print line } }'; }

total=$(wc -l <"$rows" | tr -d ' ')
n_remove=$(awk -F '\t' '$1=="remove"' "$rows" | wc -l | tr -d ' ')
n_keep=$(( total - n_remove ))

echo "repo:      $repo"
if [ "$apply" = yes ]; then echo "mode:      APPLY (removes worktrees and deletes their local branches)"
else echo "mode:      dry run (nothing is changed; pass --apply to remove)"; fi
echo "pr lookup: $pr_lookup_note"
echo "worktrees: $total examined, $n_remove to remove, $n_keep kept"
echo

echo "CANDIDATES"
if [ "$n_remove" -eq 0 ]; then
    echo "  none"
else
    { printf 'BRANCH\tPR\tSTATE\tSIZE\tLAST COMMIT\tREMOTE\tWORKTREE\n'
      awk -F '\t' '$1=="remove" { printf "%s\t#%s\t%s\t%s\t%s\t%s\t%s\n", $2,$3,$4,$5,$6,$7,$10 }' "$rows"
    } | align | sed 's/^/  /'
fi
echo

echo "KEPT"
{ printf 'BRANCH\tREASON\tWORKTREE\n'
  awk -F '\t' '$1=="keep" { printf "%s\t%s\t%s\n", $2,$9,$10 }' "$rows"
} | align | sed 's/^/  /'
echo

if [ "$apply" != yes ]; then
    echo "Dry run. Re-run with --apply to remove the $n_remove candidate(s) above."
    exit 0
fi

fail=0
while IFS=$'\t' read -r branch scanned_head pr_oid wt; do
    echo "removing $wt ($branch)"
    # The verdict above was decided when the scan ran, and the scan takes
    # roughly a minute on a large tree. Another agent can commit in that
    # window, leaving a clean worktree that `git worktree remove` accepts and
    # a branch that `git branch -D` force-deletes along with the new commit.
    # Re-derive the two facts that can move before touching anything.
    live_head=$(git -C "$wt" rev-parse HEAD 2>/dev/null)
    if [ "$live_head" != "$scanned_head" ]; then
        echo "  SKIPPED: HEAD moved to ${live_head:-unreadable} since the scan" >&2
        fail=1
        continue
    fi
    if ! worktree_is_clean "$wt"; then
        echo "  SKIPPED: the working tree is no longer clean" >&2
        fail=1
        continue
    fi
    live_remote=$(compute_remote "$wt" "$pr_oid")
    if ! remote_is_safe "$live_remote"; then
        echo "  SKIPPED: now holds commits the PR never received ($live_remote)" >&2
        fail=1
        continue
    fi
    if git worktree remove "$wt" 2>"$work/rm.err"; then
        echo "  worktree removed"
    else
        echo "  FAILED to remove worktree: $(cat "$work/rm.err")" >&2
        fail=1
        continue
    fi
    if git branch -D "$branch" >/dev/null 2>"$work/br.err"; then
        echo "  branch $branch deleted"
    else
        echo "  FAILED to delete branch $branch: $(cat "$work/br.err")" >&2
        fail=1
    fi
done < <(awk -F '\t' '$1=="remove" { printf "%s\t%s\t%s\t%s\n", $2, $11, $12, $10 }' "$rows")

echo
echo "git worktree list now:"
git worktree list | sed 's/^/  /'
exit "$fail"
