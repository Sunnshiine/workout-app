# shellcheck shell=bash
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
prune="$script_dir/../prune-merged-worktrees.sh"
[ -x "$prune" ] || { echo "not executable: $prune" >&2; exit 2; }

root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
# git reports physical paths, and on macOS mktemp hands back /var, a symlink to
# /private/var. Resolve once so assertions can compare paths exactly.
root=$(cd "$root" && pwd -P)
pass=0
fail=0

say() { printf '%s\n' "$*"; }
ok()   { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

kept()       { awk '/^KEPT$/{f=1;next} f' "$root/out.txt"; }
