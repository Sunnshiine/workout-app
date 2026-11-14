#!/bin/bash
# scripts/contact-sheet.sh runs the tiler from a compiled copy. A fake swiftc builds a shell script that
# says which source it was built from, a fake swift stands in for running contact-sheet.swift by path,
# and fake-hostgate stands in for the slot, so no test compiles anything or takes a host slot.
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
repo=$root/repo
mkdir -p "$repo/scripts" "$root/bin" "$root/usage"
find "$script_dir/.." -maxdepth 1 -type f -exec cp {} "$repo/scripts/" \;
cp "$script_dir/fake-hostgate" "$root/bin/hostgate"
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '    got:  %s\n    want: %s\n' "$2" "$3"; fi; }

# The built "tiler" prints the md5 of the source it was built from and its arguments, then exits
# FAKE_TILER_RC. FAKE_SWIFTC_SLOW=1 makes the output executable first and whole a second later, so a
# run that executed it early would print nothing. It signs the whole output ad hoc, as the linker signs
# a real one, so a later edit breaks the signature. FAKE_SWIFTC_FAIL=1 leaves a partial output and fails,
# and FAKE_SWIFTC_NOTHING=1 exits 0 having written nothing.
cat >"$root/swiftc" <<STUB
#!/bin/sh
echo "swiftc \$*" >> "$root/calls"
out= src=
while [ \$# -gt 0 ]; do
  case \$1 in -o) out=\$2; shift 2 ;; -*) shift ;; *) src=\$1; shift ;; esac
done
[ -z "\${FAKE_SWIFTC_NOTHING:-}" ] || exit 0
printf '#!/bin/sh\n' > "\$out"
chmod +x "\$out"
[ -z "\${FAKE_SWIFTC_FAIL:-}" ] || { echo "error: fake swiftc failed" >&2; exit 1; }
[ -z "\${FAKE_SWIFTC_SLOW:-}" ] || sleep 1
printf 'echo "built from %s: \$*"\nexit \${FAKE_TILER_RC:-0}\n' "\$(md5 -q "\$src")" >> "\$out"
codesign -s - "\$out" 2>/dev/null
STUB
cat >"$root/bin/swift" <<STUB
#!/bin/sh
echo "swift \$*" >> "$root/calls"
shift
echo "as a script: \$*"
STUB
chmod +x "$root/swiftc" "$root/bin/swift" "$root/bin/hostgate"

reset() { rm -rf "$root/cache" "$root/calls" "$root/slots"; touch "$root/calls"; }
tile() {
    PATH="$root/bin:$PATH" CONTACT_SHEET_CACHE="$root/cache" CONTACT_SHEET_SWIFTC="${CONTACT_SHEET_SWIFTC:-$root/swiftc}" \
        WORKOUT_DEV_USAGE_DIR="$root/usage" FAKE_HOSTGATE_LOG="$root/slots" \
        "$repo/scripts/contact-sheet.sh" "$@"
}
run() { tile "$@" >"$root/out" 2>"$root/err"; status=$?; }
built() { printf 'built from %s: %s' "$(md5 -q "$repo/scripts/contact-sheet.swift")" "$*"; }
compiles() { grep -c '^swiftc ' "$root/calls" | tr -d ' '; }
scripted() { grep -c '^swift ' "$root/calls" | tr -d ' '; }
binaries() { find "$root/cache" -maxdepth 1 -name 'contact-sheet-*' 2>/dev/null | wc -l | tr -d ' '; }
leftovers() { find "$root/cache" -maxdepth 1 -name '.build.*' 2>/dev/null | wc -l | tr -d ' '; }
fallback_line() { sed -e 's/(log: [^)]*)/(log: L)/' "$root/err"; }

echo "a miss builds the tiler once in a slot; a hit runs no compiler"
reset
run out.png a.png
expect "the first call builds in a slot labelled workout-app:contact-sheet.sh, waiting 0 s for one" \
    "$status $(compiles) $(scripted) $(cut -d' ' -f1-3 "$root/slots") $(grep -c " $root/swiftc -O -o " "$root/slots")" \
    "0 1 0 label=workout-app:contact-sheet.sh wait=0 nested=no 1"
expect "and runs what it built, saying nothing else" "$(cat "$root/out")|$(cat "$root/err")" "$(built out.png a.png)|"
run --crop 1,2,3,4 out.png a.png
expect "the next call runs the cached binary and no swiftc, swift or slot" \
    "$status $(compiles) $(scripted) $(wc -l <"$root/slots" | tr -d ' ')" "0 1 0 1"
expect "with every argument" "$(cat "$root/out")|$(cat "$root/err")" "$(built --crop 1,2,3,4 out.png a.png)|"
expect "one binary, no build left behind" "$(binaries) $(leftovers)" "1 0"

echo "a changed source or compiler builds a new binary"
cp "$repo/scripts/contact-sheet.swift" "$root/contact-sheet.swift.orig"
printf '// edited\n' >>"$repo/scripts/contact-sheet.swift"
run out.png a.png
expect "an edited source misses, and its own build runs" "$status $(compiles) $(cat "$root/out")" "0 2 $(built out.png a.png)"
cp "$root/contact-sheet.swift.orig" "$repo/scripts/contact-sheet.swift"
run out.png a.png
expect "the original source hits its own binary again" "$status $(compiles) $(cat "$root/out")" "0 2 $(built out.png a.png)"
printf '\n' >>"$root/swiftc"
run out.png a.png
expect "a different compiler misses" "$status $(compiles) $(binaries)" "0 3 3"

echo "a cached binary that would not run is built again, and the shot still comes out"
# A truncated or edited Mach-O passes exec and is then killed for its signature (exit 137), so the
# signature is checked before exec. A signed file the kernel cannot exec fails exec itself.
cached() { find "$root/cache" -maxdepth 1 -name 'contact-sheet-*'; }
for broken in truncated edited unexecutable; do
    reset
    run out.png a.png
    bin=$(cached)
    case $broken in
        truncated) head -c 40 "$bin" >"$root/cut" && cat "$root/cut" >"$bin" ;;
        edited) printf 'echo "a stranger wrote this"\n' >>"$bin" ;;
        unexecutable) printf '#!%s/no-such-interpreter\n' "$root" >"$bin" && codesign -f -s - "$bin" 2>/dev/null ;;
    esac
    run out.png a.png
    expect "a $broken binary at the key is replaced: the shot comes out of a new build" \
        "$status $(compiles) $(scripted) $(cat "$root/out")" "0 2 0 $(built out.png a.png)"
    expect "with one line naming why, after any line exec printed" "$(tail -1 "$root/err" | sed "s|$bin|BIN|")" \
        "contact-sheet.sh: the cached tiler BIN would not run, so it is built again"
    run out.png a.png
    expect "and the next call hits the new one" "$status $(compiles) $(cat "$root/err")" "0 2 "
done

echo "the tiler's own exit passes through, and nothing runs it twice"
reset
FAKE_TILER_RC=66 run out.png notes.txt
expect "a miss exits as the tiler does" "$status $(compiles) $(scripted)" "66 1 0"
FAKE_TILER_RC=64 run
expect "a hit exits as the tiler does" "$status $(compiles) $(scripted)" "64 1 0"

echo "a shot is never refused: when the slot, the build or the cache fails, the script runs once"
reset
FAKE_HOSTGATE_GIVE_UP=1 CONTACT_SHEET_WAIT=5 run out.png a.png
expect "a slot that never frees, waited CONTACT_SHEET_WAIT, falls back" \
    "$status $(compiles) $(scripted) $(cat "$root/out") $(cut -d' ' -f2 "$root/slots")" \
    "0 0 1 as a script: out.png a.png wait=5"
expect "with one line naming why" "$(cat "$root/err")" \
    "contact-sheet.sh: every host-wide build slot is busy (waited 5 s for one), so this call runs contact-sheet.swift as a script, which compiles it outside a slot"
expect "and leaves nothing in the cache" "$(binaries) $(leftovers)" "0 0"
FAKE_HOSTGATE_GIVE_UP=1 run out.png a.png
expect "the next miss tries the slot again" "$status $(wc -l <"$root/slots" | tr -d ' ') $(scripted)" "0 2 2"
reset
FAKE_SWIFTC_FAIL=1 run out.png a.png
expect "a failed build falls back" "$status $(compiles) $(scripted) $(cat "$root/out")" "0 1 1 as a script: out.png a.png"
expect "with one line naming why" "$(fallback_line)" \
    "contact-sheet.sh: swiftc failed to build the tiler with exit 1 (log: L), so this call runs contact-sheet.swift as a script, which compiles it outside a slot"
expect "and leaves no binary, partial or whole, in the cache" "$(binaries) $(find "$root/cache" -name contact-sheet | wc -l | tr -d ' ')" "0 0"
run out.png a.png
expect "so the next call builds again and runs the whole one" "$status $(compiles) $(cat "$root/out")" "0 2 $(built out.png a.png)"
reset
FAKE_SWIFTC_NOTHING=1 run out.png a.png
expect "a build that exits 0 with no binary falls back" "$status $(scripted) $(fallback_line | cut -d'(' -f1)" \
    "0 1 contact-sheet.sh: the tiler build left no binary "
reset
CONTACT_SHEET_SWIFTC=$root/no-swiftc run out.png a.png
expect "a missing swiftc falls back" "$status $(scripted) $(cat "$root/err" | cut -d, -f1)" \
    "0 1 contact-sheet.sh: no swiftc at '$root/no-swiftc'"
reset
printf 'a file\n' >"$root/cache"
run out.png a.png
expect "a cache it cannot write falls back" "$status $(compiles) $(scripted) $(cut -d, -f1 "$root/err")" \
    "0 0 1 contact-sheet.sh: cannot write the tiler cache at $root/cache"

echo "concurrent first calls never run a partial binary, and leave one"
reset
FAKE_SWIFTC_SLOW=1 tile first.png a.png >"$root/out-0" 2>&1 &
pids=($!)
waited=0
while [ "$(compiles)" = 0 ] && [ $waited -lt 100 ]; do sleep 0.1; waited=$((waited + 1)); done
for i in 1 2 3 4 5; do
    FAKE_SWIFTC_SLOW=1 tile "late-$i.png" a.png >"$root/out-$i" 2>&1 &
    pids+=($!)
done
statuses=
for pid in "${pids[@]}"; do wait "$pid"; statuses="$statuses$?"; done
wrong=
for i in 1 2 3 4 5; do
    [ "$(cat "$root/out-$i")" = "$(built "late-$i.png" a.png)" ] || wrong="$wrong $i:$(cat "$root/out-$i")"
done
expect "every call exits 0 with the whole tiler's output" "$statuses $(cat "$root/out-0")$wrong" "000000 $(built first.png a.png)"
expect "the cache holds one binary and no build" "$(binaries) $(leftovers)" "1 0"
expect "and it is whole" "$(tail -1 "$root/cache"/contact-sheet-*)" 'exit ${FAKE_TILER_RC:-0}'

echo "with no CONTACT_SHEET_CACHE the cache is the main checkout's, shared by its worktrees"
reset
git -C "$repo" init -q && git -C "$repo" add -A && git -C "$repo" -c user.name=t -c user.email=t@example.com commit -qm t
git -C "$repo" worktree add -q "$root/lane" 2>/dev/null
PATH="$root/bin:$PATH" CONTACT_SHEET_SWIFTC="$root/swiftc" WORKOUT_DEV_USAGE_DIR="$root/usage" \
    "$root/lane/scripts/contact-sheet.sh" out.png a.png >"$root/out" 2>"$root/err"
expect "a worktree's first call builds into the main checkout" \
    "$? $(compiles) $(find "$repo/.claude/work/contact-sheet" -name 'contact-sheet-*' | wc -l | tr -d ' ')" "0 1 1"
PATH="$root/bin:$PATH" CONTACT_SHEET_SWIFTC="$root/swiftc" WORKOUT_DEV_USAGE_DIR="$root/usage" \
    "$repo/scripts/contact-sheet.sh" out.png a.png >"$root/out" 2>"$root/err"
expect "and the main checkout's call hits it" "$? $(compiles) $(cat "$root/err")" "0 1 "

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
