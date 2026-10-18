# shellcheck shell=bash
# Sourced by verify.sh.

resolve_sim() {
  [ -n "$sim" ] && return 0
  if [ -z "${SIM:-}" ]; then
    cat >&2 <<'EOF'
SIM is not set. verify.sh drives only the simulator you name, because the stock iPhone 17 Pro is shared and another agent's app may be on it (issue 660).
Make a lane simulator once and pass it on every call:
  export SIM=$(xcrun simctl create LANE_NAME "iPhone 17 Pro" com.apple.CoreSimulator.SimRuntime.iOS-27-0)
EOF
    exit 2
  fi
  local picked
  picked=$(pick_sim "$SIM") || exit
  read -r sim _ <<< "$picked"
  state_dir=/tmp/workout-verify-$sim
}

ensure_axe() {
  [ -x "$axe" ] && return
  echo "installing the accessibility driver into $work (once)" >&2
  mkdir -p "$work"
  npm install --prefix "$work" --no-save --silent --no-audit --no-fund xcodebuildmcp@2.7.0 >/dev/null
  [ -x "$axe" ] || { echo "axe not found after install: $axe" >&2; exit 65; }
}

main_root() {
  local common
  common=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir) || exit
  dirname "$common"
}

lane() {
  local branch
  if branch=$(git -C "$repo" symbolic-ref --short -q HEAD); then
    printf '%s\n' "$branch" | tr -c 'A-Za-z0-9._\n-' '-'
  else
    printf 'detached-%s\n' "$(basename "$repo")"
  fi
}

evidence_base() {
  if [ -n "${VERIFY_EVIDENCE:-}" ]; then printf '%s\n' "$VERIFY_EVIDENCE"; return 0; fi
  printf '%s/.claude/work/evidence/%s\n' "$(main_root)" "$(lane)"
}

current_run() {
  if [ -n "${VERIFY_RUN:-}" ]; then printf '%s\n' "$VERIFY_RUN"; return 0; fi
  [ -n "$sim" ] || [ -n "${SIM:-}" ] || return 0
  resolve_sim
  [ -f "$state_dir/run" ] && cat "$state_dir/run"
  return 0
}

begin_run() {
  local name=${VERIFY_RUN:-$(date +%Y%m%d-%H%M%S)}
  rm -f "$state_dir/reclaimed.$name"
  mkdir -p "$state_dir"
  printf '%s\n' "$name" > "$state_dir/run"
  if [ -n "${VERIFY_RUN:-}" ]; then rm -f "$state_dir/unnamed"; else : > "$state_dir/unnamed"; fi
  printf '%s\n' "$name"
}

run_dir() {
  local name base
  name=$(current_run)
  [ -n "$name" ] || name=$(begin_run)
  base=$(evidence_base)
  mkdir -p "$base/$name"
  printf '%s\n' "$base/$name"
}

recorded_run_dir() {
  local name base
  name=$(current_run) || exit
  base=$(evidence_base) || exit
  if [ -n "$name" ] && [ -d "$base/$name" ]; then
    printf '%s\n' "$base/$name"
    return 0
  fi
  echo "no evidence directory for this run in $base; name one: VERIFY_RUN=<run> $0 $cmd ..." >&2
  echo "recent runs:" >&2
  ls -t "$base" 2>/dev/null | head -3 | sed 's/^/  /' >&2 || true
  return 1
}

valid_name() {
  case ${1:-} in
    ""|-*|*[!A-Za-z0-9-]*)
      echo "a run or shot name is letters, digits and dashes, starting with a letter or digit: ${1:-}" >&2
      exit 2
      ;;
  esac
}

shot_names() {
  ls -tr "$1"/*.tree.txt 2>/dev/null | sed 's|.*/||; s|\.tree\.txt$||' || true
}

capture() {
  local err
  if ! err=$("$axe" screenshot --udid "$sim" --output "$1" 2>&1 >/dev/null); then
    printf '%s\n' "$err" >&2
    echo "axe screenshot failed: $1" >&2
    exit 70
  fi
}

refuse_unmoved_frame() {
  local dir=$1 new=$2/$3 name=$3 newest changes
  newest=$(shot_names "$dir" | tail -1)
  [ -n "$newest" ] || return 0
  cmp -s "$dir/$newest.png" "$new.png" || return 0
  changes=$(python3 "$tree" diff "$dir/$newest.tree.txt" "$new.tree.txt")
  case $changes in "no tree changes "*) return 0 ;; esac
  rm -f "$new.png" "$new.tree.txt"
  {
    echo "refused $name: its frame is byte-identical to $newest.png but its tree changed, so the pixels did not move while the tree did"
    printf '%s\n' "$changes"
    echo "if those lines are text the app does not draw, $newest.png already shows this screen and the lines are the evidence"
    echo "if not, the shot fired before a transition drew (wait a second and shoot again) or the screenshot pipeline is wedged, as the axe button lock in issue 674 left it, and $newest.png may be frozen too (run: xcrun simctl shutdown $sim, then SIM=$sim VERIFY_RUN=${dir##*/} $0 launch <fixture>, and shoot $newest again)"
  } >&2
  exit 70
}

app_path() {
  for plist in ~/Library/Developer/Xcode/DerivedData/WorkoutTracker-*/info.plist; do
    if [ "$(plutil -extract WorkspacePath raw "$plist")" = "$project" ]; then
      echo "$(dirname "$plist")/Build/Products/Debug-iphonesimulator/WorkoutTracker.app"
      return
    fi
  done
}

describe() { "$axe" describe-ui --udid "$sim"; }
front_pid() { describe 2>/dev/null | python3 "$tree" pid 2>/dev/null || echo none; }
