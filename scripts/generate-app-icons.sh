#!/usr/bin/env bash
# Renders the app-icon SVG sources (docs/design/app-icon/) into the 1024×1024
# asset-catalog PNGs. Chromium is the reference rasterizer — the glass recipe
# leans on SVG filters that other rasterizers render differently.
#
# Usage: scripts/generate-app-icons.sh
#   CHROME=/path/to/chrome to override the browser binary.
#
# Requires python3 with Pillow: the App Store "any" icon must be RGB with no
# alpha channel (ITMS-90717), while the tinted variant must keep its alpha.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
src="$repo_root/docs/design/app-icon"
catalog="$repo_root/WorkoutTracker/Assets.xcassets"
# Prefer a headless-shell build: full browser builds reserve window chrome
# even in headless mode, which shrinks the viewport below --window-size and
# leaves a dead band at the bottom of the capture.
default_chrome="$(ls -d /opt/pw-browsers/chromium_headless_shell-*/chrome-linux/headless_shell 2>/dev/null | head -1)"
chrome="${CHROME:-${default_chrome:-$(command -v chromium || command -v chromium-browser || command -v google-chrome)}}"

render() { # render <svg> <png>
  "$chrome" --headless --no-sandbox --disable-gpu --hide-scrollbars \
    --window-size=1024,1024 --default-background-color=00000000 \
    --screenshot="$2" "file://$1" 2>/dev/null
}

flatten() { # flatten <png>  — strip alpha, force RGB
  python3 - "$1" <<'EOF'
import sys
from PIL import Image
path = sys.argv[1]
img = Image.open(path).convert("RGB")
img.save(path)
EOF
}

out_app="$catalog/AppIcon.appiconset"
out_dev="$catalog/AppIconDev.appiconset"

render "$src/appicon-light.svg"      "$out_app/Icon-1024.png";        flatten "$out_app/Icon-1024.png"
render "$src/appicon-dark.svg"       "$out_app/Icon-1024-dark.png";   flatten "$out_app/Icon-1024-dark.png"
render "$src/appicon-tinted.svg"     "$out_app/Icon-1024-tinted.png"  # keeps alpha
render "$src/appicon-dev-light.svg"  "$out_dev/Icon-1024.png";        flatten "$out_dev/Icon-1024.png"
render "$src/appicon-dev-dark.svg"   "$out_dev/Icon-1024-dark.png";   flatten "$out_dev/Icon-1024-dark.png"
cp "$out_app/Icon-1024-tinted.png"   "$out_dev/Icon-1024-tinted.png"  # tinted is flavor-agnostic

echo "Rendered app icons into $out_app and $out_dev"
