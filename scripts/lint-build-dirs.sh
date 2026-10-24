#!/bin/bash
# Fails when a script under scripts/ or .agents/ names a .build/<dir> that scripts/build-dirs.sh
# lists in neither results_dirs nor regenerable_dirs, when a dir is in both, or when a list names
# a dir no script does. Exits 0 when clean, 1 otherwise.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/build-dirs.sh
. "$root/scripts/build-dirs.sh"

named=$(cd "$root" && grep -rnoE --include='*.sh' --include='*.py' --exclude-dir=tests \
    '\.build/[A-Za-z0-9_-]+' scripts .agents | sort || true)
dirs=$(sed 's|.*:\.build/||' <<<"$named" | sort -u)
status=0
# ${a[@]+...} because bash 3.2 calls an empty array unbound under set -u.
for d in ${results_dirs[@]+"${results_dirs[@]}"}; do
    case " ${regenerable_dirs[*]-} " in
        *" $d "*) echo "scripts/build-dirs.sh lists $d in both results_dirs and regenerable_dirs; keep one"; status=1 ;;
    esac
done
listed=" ${results_dirs[*]-} ${regenerable_dirs[*]-} "
while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    d=${hit##*:.build/}
    case $listed in *" $d "*) continue ;; esac
    echo "${hit%:*} names .build/$d, which scripts/build-dirs.sh lists in neither results_dirs" \
        "(lane.sh down saves it) nor regenerable_dirs (down drops it); add it to one"
    status=1
done <<<"$named"
for d in ${results_dirs[@]+"${results_dirs[@]}"} ${regenerable_dirs[@]+"${regenerable_dirs[@]}"}; do
    grep -qxF "$d" <<<"$dirs" || {
        echo "scripts/build-dirs.sh lists $d, which no script names as .build/$d; remove it"
        status=1
    }
done
[ "$status" -ne 0 ] || echo "==> Clean: $(grep -c . <<<"$dirs") .build dirs scripts name, each in one list"
exit "$status"
