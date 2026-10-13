#!/bin/bash
# shellcheck disable=SC2016  # in_tree commands expand inside the sourcing shell
set -uo pipefail

lib=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scratch-tree.sh
root=$(mktemp -d) || exit 3
root=$(cd "$root" && pwd -P)
trap 'rm -f "$root"/gate*; sleep 0.3; rm -rf "$root"' EXIT
repo=$root/repo
export pool=$repo/.build/scratch locks=$repo/.git/scratch-locks
export LC_ALL=C GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=false
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
expect() {
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '    got:\n%s\n    want:\n%s\n' "$2" "$3"; fi
}
in_tree() { (cd "$1" && shift && /bin/bash -c "set -euo pipefail; . '$lib'; $1"); }
wait_for() { local _; for _ in $(seq 1 100); do [ -e "$1" ] && return; sleep 0.05; done; }

git init -q -b main "$repo"
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name t
printf '.build/\nSecrets.xcconfig\n' >"$repo/.gitignore"
echo a >"$repo/a.txt"
echo b >"$repo/b.txt"
git -C "$repo" add -A
git -C "$repo" commit -qm base

echo a-edited >"$repo/a.txt"
echo c >"$repo/c.txt"
git -C "$repo" add c.txt
echo d >"$repo/d.txt"
mkdir -p "$repo/.build" && echo ignored >"$repo/.build/x"
before=$(git -C "$repo" status --porcelain; shasum "$repo/.git/index" "$repo"/*.txt)
tree=$(in_tree "$repo" scratch_snapshot)
after=$(git -C "$repo" status --porcelain; shasum "$repo/.git/index" "$repo"/*.txt)
expect "a snapshot holds staged, unstaged, and untracked files and skips ignored ones" \
    "$(git -C "$repo" ls-tree -r --name-only "$tree" | tr '\n' ' '; git -C "$repo" show "$tree:a.txt")" \
    ".gitignore a.txt b.txt c.txt d.txt a-edited"
expect "a snapshot leaves the caller's index and files alone" "$after" "$before"
git -C "$repo" reset -q --hard && git -C "$repo" clean -fdq

git -C "$repo" worktree add -q "$root/wt" -b side
echo b-edited >"$root/wt/b.txt"
echo e >"$root/wt/e.txt"
echo secret >"$root/wt/Secrets.xcconfig"
got=$(in_tree "$root/wt" 'scratch_claim t; scratch_sync HEAD "$(scratch_snapshot)"; echo "$scratch"
    git -C "$scratch" rev-parse --show-toplevel; ls "$scratch"; cat "$scratch/b.txt" "$scratch/Secrets.xcconfig" "$locks/1.owner"')
expect "a claim from a linked worktree syncs its working state into slot 1 of the primary checkout's pool" "$got" \
"$pool/1
$pool/1
Secrets.xcconfig
a.txt
b.txt
e.txt
b-edited
secret
$root/wt"

echo junk >"$pool/1/b.txt"
echo junk >"$pool/1/junk.txt"
rm "$pool/1/a.txt"
mkdir -p "$pool/1/.build" && echo warm >"$pool/1/.build/warm"
got=$(in_tree "$root/wt" 'scratch_claim t; scratch_sync main; echo "$scratch"; ls "$scratch"; cat "$scratch/b.txt" "$scratch/.build/warm"
    git -C "$scratch" status --porcelain')
expect "a sync converges from a crashed run's leftovers and keeps ignored files" "$got" \
"$pool/1
Secrets.xcconfig
a.txt
b.txt
b
warm"

hold() {
    touch "$root/gate$1"
    (cd "$repo" && /bin/bash -c ". '$lib'; scratch_claim 'holder $1'; echo \$\$ >'$root/pid$1'
        (while [ -e '$root/gate$1' ]; do sleep 0.05; done) & echo \$! >'$root/child$1'; wait") 2>/dev/null &
    wait_for "$root/child$1"
}
hold 1
got=$(in_tree "$repo" 'scratch_claim t; echo "$scratch"')
expect "a claim skips a held slot" "$got" "$pool/2"
git -C "$repo" clean -fdxq
got=$(SCRATCH_SLOTS=1 in_tree "$repo" 'scratch_claim t; echo "$scratch"' 2>/dev/null)
expect "git clean -fdx in the primary checkout never frees a held slot" "$?" 75
hold 2
got=$(SCRATCH_SLOTS=2 in_tree "$repo" 'scratch_claim t; echo "$scratch"' 2>&1)
status=$?
expect "a claim with every slot held exits 75 naming each holder" "$status $got" \
"75 every scratch tree is busy; wait for one to finish (lsof $locks/*.lock lists every holder):
  $pool/1: holder 1 (pid $(cat "$root/pid1"))
  $pool/2: holder 2 (pid $(cat "$root/pid2"))"

kill -9 "$(cat "$root/pid1")"
sleep 0.2
got=$(SCRATCH_SLOTS=1 in_tree "$repo" 'scratch_claim t; echo "$scratch"; cat "$locks/1.lock" | sed "s/$$/SELF/"')
expect "a claim kills what a dead holder left running in its slot and takes the slot" "$got
$(if kill -0 "$(cat "$root/child1")" 2>/dev/null; then echo "the leftover still runs"; else echo "the leftover is gone"; fi)" \
"$pool/1
t (pid SELF)
the leftover is gone"
rm "$root/gate1" "$root/gate2"

sh -c 'exit 0' & dead=$!
wait $dead
(python3 -c 'import fcntl, os, sys, time
fcntl.flock(8, fcntl.LOCK_EX)
os.setsid()
time.sleep(30)' 8>>"$locks/1.lock" & echo $! >"$root/leftover")
leftover=$(cat "$root/leftover")
sleep 0.3
echo "dead run (pid $dead)" >"$locks/1.lock"
python3 -c 'import fcntl, sys, time
claim = open(sys.argv[1] + "/claim.lock", "a")
fcntl.flock(claim, fcntl.LOCK_EX)
probing = open(sys.argv[1] + "/1.lock", "a")
open(sys.argv[2], "w").close()
time.sleep(1)' "$locks" "$root/probing" &
prober=$!
wait_for "$root/probing"
got=$(SCRATCH_SLOTS=1 in_tree "$repo" 'scratch_claim t; echo "$scratch"')
wait $prober
prober_status=$?
expect "a reclaim kills a dead run's leftover but never a claim still probing that slot" "$got
prober exit $prober_status
$(if kill -0 $leftover 2>/dev/null; then echo "the leftover still runs"; else echo "the leftover is gone"; fi)" "$pool/1
prober exit 0
the leftover is gone"

got=$(GIT_CONFIG_VALUE_0=true in_tree "$repo" 'scratch_claim t; scratch_sync HEAD; git -C "$scratch" status --porcelain'
    SCRATCH_SLOTS=1 in_tree "$repo" 'scratch_claim t; echo "$scratch"')
expect "a git fsmonitor daemon started in a slot never holds its lock" "$got" "$pool/1"

mkdir -p "$root/hooks"
printf '#!/bin/sh\necho ran >>"%s/hook-ran"\nexit 1\n' "$root" >"$root/hooks/post-checkout"
chmod +x "$root/hooks/post-checkout"
git -C "$repo" config core.hooksPath "$root/hooks"
got=$(SCRATCH_SLOTS=1 in_tree "$repo" 'scratch_claim t; scratch_sync HEAD; echo x >"$scratch/a.txt"
    git -C "$scratch" checkout -q HEAD -- a.txt; cat "$scratch/a.txt"' 2>&1; cat "$root/hook-ran" 2>/dev/null)
expect "a scratch checkout never runs the repo's post-checkout hook" "$got" "a"
git -C "$repo" config --unset core.hooksPath

hold 3
mkdir -p "$pool/2/.build" "$root/DerivedData/WorkoutTracker-abc" "$root/DerivedData/WorkoutTracker-other" "$root/DerivedData/WorkoutTracker-gone"
plutil -create xml1 "$root/DerivedData/WorkoutTracker-abc/info.plist"
plutil -insert WorkspacePath -string "$pool/2/WorkoutTracker.xcodeproj" "$root/DerivedData/WorkoutTracker-abc/info.plist"
cp "$root/DerivedData/WorkoutTracker-abc/info.plist" "$root/DerivedData/WorkoutTracker-other/info.plist"
plutil -replace WorkspacePath -string "$root/elsewhere/WorkoutTracker.xcodeproj" "$root/DerivedData/WorkoutTracker-other/info.plist"
cp "$root/DerivedData/WorkoutTracker-abc/info.plist" "$root/DerivedData/WorkoutTracker-gone/info.plist"
plutil -replace WorkspacePath -string "$pool/7/WorkoutTracker.xcodeproj" "$root/DerivedData/WorkoutTracker-gone/info.plist"
got=$(HOME=$root/home in_tree "$repo" 'mkdir -p ~/Library/Developer/Xcode && ln -s "'"$root"'/DerivedData" ~/Library/Developer/Xcode/DerivedData
    scratch_clean | sed -E "s/\(([0-9]+) MB\)/(N MB)/"; ls "'"$root"'/DerivedData"; ls "$pool"; git worktree list | grep -c "$pool/"')
expect "a clean removes every slot no live run holds, with the DerivedData built from it even when its folder is gone, and keeps a held one" "$got" \
"kept $pool/1: holder 3 (pid $(cat "$root/pid3"))
removed $pool/2 (N MB)
removed $pool/7 (N MB)
WorkoutTracker-other
1
1"
rm "$root/gate3"

rm -rf "$pool/1"
got=$(in_tree "$repo" 'scratch_claim t; git -C "$scratch" rev-parse --show-toplevel; ls "$scratch"')
expect "a deleted slot is rebuilt" "$got" "$pool/1
a.txt
b.txt"
echo "gitdir: $root/nowhere" >"$pool/1/.git"
got=$(in_tree "$repo" 'scratch_claim t; git -C "$scratch" rev-parse --show-toplevel; ls "$scratch"')
expect "a slot whose worktree link is broken is rebuilt" "$got" "$pool/1
a.txt
b.txt"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
