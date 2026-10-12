#!/bin/bash
set -uo pipefail

script=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/snapshot-diffs.sh
root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
bundle=$root/run.xcresult
mkdir -p "$root/bin" "$bundle"
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

# Writes what `xcresulttool export attachments` writes for a real visual run: UUID-named files and
# a manifest.json that maps them to tests. $STUB_MANIFEST picks the manifest.
cat >"$root/bin/xcrun" <<'STUB'
#!/bin/sh
[ "$1 $2 $3 $4 $6" = "xcresulttool export attachments --path --output-path" ] || exit 64
cp "$STUB_MANIFEST" "$7/manifest.json"
for name in $(grep -o '"[0-9A-F-]*\.[a-z]*"' "$STUB_MANIFEST" | tr -d '"'); do echo "$name" >"$7/$name"; done
STUB
chmod +x "$root/bin/xcrun"

attachment() {
    printf '{"exportedFileName": "%s", "isAssociatedWithFailure": %s, "suggestedHumanReadableName": "%s"}' "$1" "$2" "$3"
}
cat >"$root/failed.json" <<EOF
[
  {"testIdentifier": "ActiveSetCardVisualTests/activeSetCardMatchesVisualBaseline()", "attachments": [
    $(attachment B57BC836-1502-4AD5-B6C3-E85655CFC9F9.png false difference_0_557DEA10-0AD3-40A6-991F-39196AD35118.png),
    $(attachment 671CC45F-3DC0-4D19-A40E-B45A2CECE58E.png false failure_0_F2BA51CB-7429-4DD6-BE75-28FBCC6237DD.png),
    $(attachment C65C36EA-4C58-4069-A522-08C6E133D9E7.png false reference_0_5B7392FA-4776-4832-B8C6-D722F2B6517F.png),
    $(attachment D47E72D6-FFFA-4469-8CE8-67EDE093A813.txt true "Complete Issue Description.txt")]},
  {"testIdentifier": "BlockGridVisualTests/passingTestThatAttachesAnImage()", "attachments": [
    $(attachment 11111111-1111-4111-8111-111111111111.png false screen_0_22222222-2222-4222-8222-222222222222.png)]},
  {"testIdentifier": "SessionStageLayoutTests/aLayoutAssertion()", "attachments": [
    $(attachment 33333333-3333-4333-8333-333333333333.txt true "Complete Issue Description.txt")]}
]
EOF
cat >"$root/none.json" <<EOF
[{"testIdentifier": "SessionStageLayoutTests/aLayoutAssertion()", "attachments": [
  $(attachment 33333333-3333-4333-8333-333333333333.txt true "Complete Issue Description.txt")]}]
EOF

diffs() {
    STUB_MANIFEST=$root/$1 PATH="$root/bin:$PATH" "$script" "${@:2}" >"$root/out" 2>"$root/err"
    status=$?
}
expect() {
    if [ "$2" = "$3" ]; then
        ok "$1"
    else
        bad "$1"
        printf '    got:\n%s\n    want:\n%s\n    stderr:\n%s\n' "$2" "$3" "$(cat "$root/err")"
    fi
}

out=$root/run-diffs/ActiveSetCardVisualTests/activeSetCardMatchesVisualBaseline
diffs failed.json "$bundle"
expect "a failed snapshot's three images print, named by kind, beside the bundle" "$status
$(cat "$root/out")
$(cat "$out/failure_0.png")" "0
$out/difference_0.png
$out/failure_0.png
$out/reference_0.png
671CC45F-3DC0-4D19-A40E-B45A2CECE58E.png"

touch "$out/stale.png"
diffs failed.json "$bundle"
expect "a rerun replaces the directory" "$status $(ls "$out" | tr '\n' ' ')" "0 difference_0.png failure_0.png reference_0.png "

diffs failed.json "$bundle" "$root/elsewhere"
expect "a second argument picks the directory" "$status $(head -1 "$root/out")" \
    "0 $root/elsewhere/ActiveSetCardVisualTests/activeSetCardMatchesVisualBaseline/difference_0.png"

diffs none.json "$bundle"
expect "a bundle whose failures attached no image exits 1 and says so" "$status $(cat "$root/out")$(cat "$root/err")" \
    "1 no failed test in $bundle attached a PNG"

diffs failed.json "$root/missing.xcresult"
expect "a missing bundle prints usage and exits 2" "$status $(head -1 "$root/err")" \
    "2 Usage: scripts/snapshot-diffs.sh <bundle.xcresult> [out-dir]"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
