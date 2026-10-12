#!/bin/bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/snapshot-diffs.sh <bundle.xcresult>
Exports the PNG images that failing tests in a result bundle attached, which for a failed Visual
Regression test are swift-snapshot-testing's reference, failure, and difference images, into
<bundle>-diffs/<Suite>/<test>/<name>.png beside the bundle, replacing that directory, and prints
each path. scripts/test-sim.sh prints the bundle path on its last line. Exits 1 with a message
when no failed test attached a PNG.
EOF
  exit 2
}

[ $# = 1 ] || usage
bundle=${1%/}
case $bundle in *.xcresult) ;; *) usage ;; esac
[ -d "$bundle" ] || usage
out=${bundle%.xcresult}-diffs
raw=$(mktemp -d)
trap 'rm -rf "$raw"' EXIT

xcrun xcresulttool export attachments --path "$bundle" --output-path "$raw" > /dev/null
rm -rf "$out"
RAW=$raw OUT=$out BUNDLE=$bundle python3 -c '
import json, os, re, shutil, sys
raw, out = os.environ["RAW"], os.environ["OUT"]
paths = []
for test in json.load(open(os.path.join(raw, "manifest.json"))):
    if not any(a["isAssociatedWithFailure"] for a in test["attachments"]):
        continue
    folder = os.path.join(out, test["testIdentifier"].replace("()", ""))
    for attachment in test["attachments"]:
        name = attachment["suggestedHumanReadableName"]
        if name.endswith(".png"):
            os.makedirs(folder, exist_ok=True)
            paths.append(os.path.join(folder, re.sub(r"_[0-9A-F-]{36}(?=\.png$)", "", name)))
            shutil.move(os.path.join(raw, attachment["exportedFileName"]), paths[-1])
if not paths:
    sys.exit("no failed test in %s attached a PNG" % os.environ["BUNDLE"])
print("\n".join(sorted(paths)))
'
