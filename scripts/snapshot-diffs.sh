#!/bin/bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/snapshot-diffs.sh <bundle.xcresult> [out-dir]
Exports the PNG images that failing tests in a result bundle attached, which for a failed Visual
Regression test are swift-snapshot-testing's reference, failure, and difference images, into
out-dir/<Suite>/<test>/<name>.png and prints each path. out-dir defaults to the bundle path with
-diffs in place of .xcresult and is replaced on every run. scripts/test-sim.sh prints the bundle
path on its last line. Exits 1 with a message when the bundle holds no such image.
EOF
  exit 2
}

[ $# -ge 1 ] && [ $# -le 2 ] && [ -d "$1" ] || usage
bundle=$1
out=${2:-${bundle%.xcresult}-diffs}
raw=$(mktemp -d)
trap 'rm -rf "$raw"' EXIT

xcrun xcresulttool export attachments --path "$bundle" --output-path "$raw" > /dev/null
rm -rf "$out"
mkdir -p "$out"
RAW=$raw OUT=$out python3 -c '
import json, os, re, shutil
raw, out = os.environ["RAW"], os.environ["OUT"]
for test in json.load(open(os.path.join(raw, "manifest.json"))):
    if not any(a["isAssociatedWithFailure"] for a in test["attachments"]):
        continue
    folder = os.path.join(out, test["testIdentifier"].replace("()", ""))
    for attachment in test["attachments"]:
        name = attachment["suggestedHumanReadableName"]
        if not name.endswith(".png"):
            continue
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, re.sub(r"_[0-9A-F-]{36}(?=\.png$)", "", name))
        shutil.move(os.path.join(raw, attachment["exportedFileName"]), path)
        print(path)
' | sort | grep . || { echo "no failed test in $bundle attached a PNG" >&2; exit 1; }
