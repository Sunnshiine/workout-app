# shellcheck shell=bash
pr_field() {
    awk -F '\t' -v b="$1" -v n="$2" '$1 == b { print $n; exit }' "$prmap"
}

# Emit NUL-delimited path/branch/head/prunable quadruples. A blank record
# terminates each worktree in the porcelain stream.
parse_worktrees() {
    local field="" wt="" branch="" head="" state=ok
    while IFS= read -r -d '' field; do
        if [ -z "$field" ]; then
            [ -n "$wt" ] && printf '%s\0%s\0%s\0%s\0' "$wt" "$branch" "$head" "$state"
            wt=""; branch=""; head=""; state=ok
        elif [ "${field#worktree }" != "$field" ]; then wt="${field#worktree }"
        elif [ "${field#branch refs/heads/}" != "$field" ]; then branch="${field#branch refs/heads/}"
        elif [ "${field#HEAD }" != "$field" ]; then head="${field#HEAD }"
        elif [ "${field#prunable}" != "$field" ]; then state=prunable
        elif [ "${field#locked}" != "$field" ]; then state=locked
        fi
    done < <(git worktree list --porcelain -z)
    [ -n "$wt" ] && printf '%s\0%s\0%s\0%s\0' "$wt" "$branch" "$head" "$state"
}

# Answers "does this worktree hold commits the PR never received". An upstream
# that still resolves answers it directly. When it does not, the branch is
# either gone (the repo deletes merged branches) or was never tracked, and both
# are answered by the SHA GitHub recorded on the PR, never by assuming nothing
# is lost.
# True when HEAD is contained in the SHA GitHub recorded on the PR, which is
# the only evidence that these commits reached the server.
pr_head_contains() {
    # pr_head_contains <worktree> <pr head oid> <head>
    [ -n "$2" ] || return 1
    [ "$2" = "$3" ] && return 0
    git -C "$1" cat-file -e "$2" 2>/dev/null \
        && git -C "$1" merge-base --is-ancestor HEAD "$2" 2>/dev/null
}

compute_remote() {
    # compute_remote <worktree> <pr head oid>
    local wt="$1" pr_oid="$2" upstream ahead head
    head=$(git -C "$wt" rev-parse HEAD 2>/dev/null) || { echo unknown; return; }
    # The exit status is load-bearing. On failure this prints the literal
    # string "@{upstream}" on stdout, so a -n test would read as success.
    if upstream=$(git -C "$wt" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) \
       && git -C "$wt" rev-parse --verify --quiet "$upstream" >/dev/null 2>&1; then
        ahead=$(git -C "$wt" rev-list --count "$upstream..HEAD" 2>/dev/null)
        case "$ahead" in
            ''|*[!0-9]*) echo unknown ;;
            # A remote-tracking ref proves only that this machine once saw the
            # branch. The server may have deleted it and nobody has pruned, so
            # the PR still has to vouch for the commits.
            0) if pr_head_contains "$wt" "$pr_oid" "$head"; then echo pushed
               else echo "pushed-unverified"; fi ;;
            *) echo "ahead:$ahead" ;;
        esac
    elif [ -n "$pr_oid" ] && [ "$pr_oid" = "$head" ]; then
        echo "gone=pr-head"
    elif pr_head_contains "$wt" "$pr_oid" "$head"; then
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
    porcelain=$(git -C "$1" status --porcelain --ignore-submodules=none 2>/dev/null) || return 1
    [ -z "$porcelain" ]
}
