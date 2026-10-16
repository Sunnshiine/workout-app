#!/bin/bash
# Renders every variant through WebKit (WKWebView), because headless Chrome crashes on this macOS.
# Serve first: python3 -m http.server 8905 --bind 127.0.0.1 (from the prototype dir).
set -e
cd "$(dirname "$0")/.."
swiftc -O tools/snap.swift -o /tmp/rest-timer-snap
out=${1:-/tmp/rest-timer-shots}; mkdir -p "$out"
base="http://127.0.0.1:8905/index.html"
while IFS='|' read name dev q; do
  [ "$dev" = se ] && wh="375 667" || wh="402 874"
  for v in ${VARIANTS:-now B2 C2 E F G}; do
    echo "== $name-$v"
    /tmp/rest-timer-snap "$base?variant=$v&capture=1&still=1$q" $wh "$out/$name-$v.png"
  done
done <<'CASES'
pro-day-rest|pro|
pro-night-rest|pro|&theme=night
se-day-rest|se|&device=se
pro-day-final|pro|&state=final
pro-night-final|pro|&state=final&theme=night
pro-day-idle|pro|&state=idle
pro-day-idle-up|pro|&state=idle&idleup=1
pro-day-expired|pro|&state=expired
CASES
