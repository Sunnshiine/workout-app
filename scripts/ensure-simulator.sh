#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/ensure-simulator.sh <device name> <iOS version> [<simulator name>]
  e.g. scripts/ensure-simulator.sh 'iPhone 17 Pro' 27.0
Prints the UDID of the simulator named <simulator name> (default: the device name) on that runtime,
creating it as that device type first when the machine has no such simulator.
Exits 1 when the device type or the runtime is missing, listing what is there instead.
EOF
  exit 2
}

[ $# -eq 2 ] || [ $# -eq 3 ] || usage
name=$1
version=$2
sim_name=${3:-$1}

plan=$(xcrun simctl list -j | NAME="$name" SIM_NAME="$sim_name" VERSION="$version" python3 -c '
import json, os, sys

name, version = os.environ["NAME"], os.environ["VERSION"]
catalog = json.load(sys.stdin)

runtimes = [r for r in catalog["runtimes"]
            if r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-") and r.get("isAvailable")]
runtime = next((r for r in runtimes if r["version"] == version), None)
if runtime is None:
    have = ", ".join(sorted(r["version"] for r in runtimes)) or "none"
    sys.exit(f"no available iOS {version} runtime. available: {have}")

existing = next((d for d in catalog["devices"].get(runtime["identifier"], [])
                 if d["name"] == os.environ["SIM_NAME"] and d.get("isAvailable")), None)
if existing:
    print(existing["udid"], "-", runtime["identifier"])
else:
    kind = next((t for t in catalog["devicetypes"] if t["name"] == name), None)
    if kind is None:
        have = "\n  ".join(t["name"] for t in catalog["devicetypes"])
        sys.exit(f"Xcode has no {name} device type. available:\n  {have}")
    print("-", kind["identifier"], runtime["identifier"])
')

read -r udid devicetype runtime <<<"$plan"
if [ "$udid" = - ]; then
  echo "creating $sim_name on iOS $version" >&2
  udid=$(xcrun simctl create "$sim_name" "$devicetype" "$runtime")
else
  echo "found $sim_name on iOS $version" >&2
fi
echo "$udid"
