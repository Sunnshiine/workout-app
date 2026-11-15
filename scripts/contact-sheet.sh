#!/bin/bash
set -uo pipefail

help() {
  cat <<'EOF_HELP'
Usage: scripts/contact-sheet.sh OUT.png IMAGE...
       scripts/contact-sheet.sh --crop X,Y,W,H OUT.png IMAGE
Runs scripts/contact-sheet.swift, the tiler, from a compiled copy, and exits as the tiler does.
Running the .swift file by path compiles it with swift-frontend on every call, outside any build slot.
The copy lives in <main checkout>/.claude/work/contact-sheet (CONTACT_SHEET_CACHE overrides it),
named for the source's bytes and the compiler's, so every worktree on the Mac shares it and an edit
to either builds a new one. A build compiles a copy of the source and is named for the copy. A miss builds it with swiftc in a host-wide slot (scripts/build-slot.sh),
waiting CONTACT_SHEET_WAIT seconds (0) for one: the build takes about as long as running the script,
so a shot never waits on a busy host, and the next miss tries again. A copy appears only whole, by
rename, so concurrent first calls never run a partial one, and a hit checks its signature first, so
a copy truncated or edited later is built again rather than run. When the slot, the build or the
cache fails, it prints one line naming why (a failed build adds its log's last lines) and runs the
.swift file by path that once.
CONTACT_SHEET_SWIFTC names the compiler (default: xcrun --find swiftc), and a build sets SDKROOT to
xcrun's macOS SDK.
EOF_HELP
}

case ${1:-} in
  -h|--help) help; exit 0 ;;
esac
here=$(cd "$(dirname "$0")" && pwd)
source=$here/contact-sheet.swift

# Prints why, then the last lines of the build log $2 when given, so a CI log shows a failed build.
as_script() {
  echo "contact-sheet.sh: $1, so this call runs contact-sheet.swift as a script, which compiles it outside a slot" >&2
  [ -z "${2:-}" ] || tail -n 10 "$2" | sed 's/^/contact-sheet.sh:   /' >&2
  exec "$source" ${args[@]+"${args[@]}"}
}

args=("$@")
swiftc=${CONTACT_SHEET_SWIFTC:-$(xcrun --find swiftc 2>/dev/null)} || as_script "xcrun found no swiftc"
[ -x "$swiftc" ] || as_script "no swiftc at '$swiftc'"
if [ -n "${CONTACT_SHEET_CACHE:-}" ]; then
  cache=$CONTACT_SHEET_CACHE
else
  common=$(git -C "$here" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
    || as_script "no git checkout holds $here, so the tiler has no cache"
  cache=$(dirname "$common")/.claude/work/contact-sheet
fi
# Asking swiftc its version runs swift-frontend, which a hit must not, so the compiler's realpath
# and stat stand for its version: a new toolchain is a new file.
compiler=$(cd "$(dirname "$swiftc")" && pwd -P)/$(basename "$swiftc")
toolchain=$(stat -L -f '%z %m %i' "$compiler") || as_script "cannot key the tiler cache"
key_of() {
  local bytes
  bytes=$(md5 -q "$1") && md5 -q -s "$bytes $compiler $toolchain"
}
key=$(key_of "$source") || as_script "cannot key the tiler cache"
binary=$cache/contact-sheet-$key

# A truncated or edited copy passes exec and is then killed for its signature, which no fallback
# can follow, so the signature is checked first; execfail returns here from a copy exec refuses.
shopt -s execfail
if [ -x "$binary" ]; then
  codesign -v "$binary" 2>/dev/null && exec "$binary" "$@"
  echo "contact-sheet.sh: the cached tiler $binary would not run, so it is built again" >&2
  rm -f "$binary"
fi

# A swiftc run bare finds no SDK and cannot load the standard library. Only some callers export
# SDKROOT (xcrun and /usr/bin/python3, so hostgate's slot), and a caller's can be another platform's,
# so the build names the macOS SDK itself.
sdk=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null) && [ -n "$sdk" ] \
  || as_script "xcrun found no macOS SDK to build the tiler against"
mkdir -p "$cache" 2>/dev/null && building=$(mktemp -d "$cache/.build.XXXXXX" 2>/dev/null) \
  || as_script "cannot write the tiler cache at $cache"
find "$cache" -maxdepth 1 -name '.build.*' -mmin +1440 -exec rm -rf {} + 2>/dev/null
# The build compiles a copy and is named for the copy's bytes, so a source that changes during the
# build (an edit, a branch switch) cannot leave the new source's binary at the old source's key.
copy=$building/contact-sheet.swift
cp "$source" "$copy" 2>/dev/null && key=$(key_of "$copy") || { rm -rf "$building"; as_script "cannot copy the tiler source into $cache"; }
binary=$cache/contact-sheet-$key
log=$building/build.log
wait=${CONTACT_SHEET_WAIT:-0}
rc=0
SDKROOT=$sdk WORKOUT_ADMIT_WAIT=$wait "$here/build-slot.sh" --as contact-sheet.sh \
  "$swiftc" -O -o "$building/contact-sheet" "$copy" >"$log" 2>&1 || rc=$?
case $rc in
  0) ;;
  75) rm -rf "$building"; as_script "every host-wide build slot is busy (waited $wait s for one)" ;;
  *) rm -f "$building/contact-sheet"; as_script "swiftc failed to build the tiler with exit $rc (log: $log)" "$log" ;;
esac
[ -s "$building/contact-sheet" ] && [ -x "$building/contact-sheet" ] \
  || as_script "the tiler build left no binary (log: $log)" "$log"
mv -f "$building/contact-sheet" "$binary" || as_script "cannot move the built tiler into $cache"
rm -rf "$building"
exec "$binary" "$@"
