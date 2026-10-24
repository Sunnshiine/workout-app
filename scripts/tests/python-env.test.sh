#!/bin/bash
set -uo pipefail

hook="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/python-env.sh"
tmp=$(mktemp -d) || exit 3
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '    got:  %s\n    want: %s\n' "$2" "$3"; fi; }

mkdir -p "$tmp/bin" "$tmp/repo" "$tmp/bare"
touch "$tmp/repo/pyproject.toml"
repo=$(cd "$tmp/repo" && pwd -P)
cat > "$tmp/bin/uv" <<'EOF'
#!/bin/bash
echo "$PWD $*" >> "$UV_CALLS"
[ -z "${UV_FAIL:-}" ] || { printf 'error: no network\nsecond line\n' >&2; exit 2; }
EOF
chmod +x "$tmp/bin/uv"
export UV_CALLS=$tmp/uv-calls PATH="$tmp/bin:$PATH"

run() { CLAUDE_PROJECT_DIR=$1 CLAUDE_ENV_FILE=$tmp/env "$hook" > "$tmp/out" 2>&1; echo $?; }

echo "a synced checkout"
expect "it exits 0 and prints nothing, so no session context is spent" "$(run "$repo") $(cat "$tmp/out")" "0 "
expect "it syncs the checkout's .venv from the lock" "$(cat "$UV_CALLS")" "$repo sync --frozen --quiet"
run "$repo" > /dev/null
expect "sourcing the env file after a second start puts .venv/bin first on PATH once" \
    "$(PATH=/usr/bin:/bin; . "$tmp/env"; echo "$PATH")" "$repo/.venv/bin:/usr/bin:/bin"

echo "a failed sync"
rm -f "$tmp/env"
expect "it still exits 0, with one line that names the fallback and uv's first error line" \
    "$(UV_FAIL=1 run "$repo") $(cat "$tmp/out")" \
    "0 scripts/python-env.sh: uv sync failed, so python3 is the system one without Pillow or numpy. Run \`uv run python3\` instead. error: no network"
expect "it leaves PATH alone" "$([ -e "$tmp/env" ] && echo written || echo absent)" "absent"

echo "a directory with no pyproject.toml"
: > "$UV_CALLS"
expect "it exits 0 without running uv" "$(run "$tmp/bare") $(cat "$tmp/out")$(cat "$UV_CALLS")" "0 "

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
