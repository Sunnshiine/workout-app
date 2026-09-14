#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: .claude/skills/verify/verify.sh <command> [args]
  build                       build WorkoutTracker for the simulator (rerun after any source change)
  launch <fixture> [ARG...]   install the built app and launch it into a fixture (extra -UITEST_* ARGs pass through)
                              fixtures: session settings onboarding long-session partial-block
                                        completed-open-exercises developer-tools
  doctor                      read-only: is the running instance ours, current, and answering?
  tree                        flat accessibility tree, one element per line: role  id  label  value  @x,y wxh
  find <id>                   one element by accessibility identifier, same line format; exit 1 if absent
  tap --id ID | --label TEXT | -x X -y Y
  hold <id> [seconds]         long press an element by identifier (default 1.2 s)
  type TEXT                   type into the focused field
  swipe up|down               scroll the screen by half its height
  shot NAME                   NAME.png and NAME.tree.txt into the evidence dir
  stop                        terminate the app this run launched; the simulator stays up
  axe ARG...                  raw axe call with --udid filled in
Environment: SIM (simulator UDID, default the booted iPhone 17 Pro, else the newest one, booted for you),
             VERIFY_RUN (evidence subdirectory, default a timestamp).
Evidence: .build/verify/evidence/<VERIFY_RUN>/  (survives stop)
EOF
  exit 2
}

repo=$(cd "$(dirname "$0")/../../.." && pwd)
project=$repo/WorkoutTracker.xcodeproj
bundle=com.sunnypatel.WorkoutTracker
work=$repo/.build/verify
axe=$work/node_modules/xcodebuildmcp/bundled/axe
run=${VERIFY_RUN:-$(date +%Y%m%d-%H%M%S)}
evidence=$work/evidence/$run

pick_sim() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
def version(runtime): return tuple(int(n) for n in runtime.rsplit("iOS-", 1)[-1].split("-"))
devices = [(version(runtime), d) for runtime, ds in json.load(sys.stdin)["devices"].items() for d in ds if d["name"] == "iPhone 17 Pro"]
booted = [d for d in devices if d[1]["state"] == "Booted"]
pick = max(booted or devices, key=lambda pair: pair[0])[1]
print(pick["udid"], pick["state"])'
}

sim=${SIM:-}
if [ -z "$sim" ]; then
  read -r sim state <<< "$(pick_sim)"
  [ "$state" = Booted ] || xcrun simctl boot "$sim"
fi
state_dir=/tmp/workout-verify-$sim

ensure_axe() {
  [ -x "$axe" ] && return
  echo "installing the accessibility driver into $work (once)" >&2
  mkdir -p "$work"
  npm install --prefix "$work" --no-save --silent --no-audit --no-fund xcodebuildmcp@2.7.0 >/dev/null
  [ -x "$axe" ] || { echo "axe not found after install: $axe" >&2; exit 65; }
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
tree=$repo/.claude/skills/verify/tree.py
front_pid() { describe 2>/dev/null | python3 "$tree" pid 2>/dev/null || echo none; }

fixture_args() {
  case $1 in
    session) echo "-UITEST_SESSION -UITEST_FULL_BLOCK" ;;
    settings) echo "-UITEST_SETTINGS -UITEST_FULL_BLOCK" ;;
    onboarding) echo "-UITEST_ONBOARDING -UITEST_FULL_BLOCK" ;;
    long-session) echo "-UITEST_SESSION -UITEST_LONG_SESSION" ;;
    partial-block) echo "" ;;
    completed-open-exercises) echo "-UITEST_SESSION -UITEST_COMPLETED_OPEN_EXERCISES" ;;
    developer-tools) echo "-UITEST_DEVELOPER_TOOLS -UITEST_FULL_BLOCK" ;;
    *) echo "unknown fixture: $1" >&2; usage ;;
  esac
}

cmd=${1:-}
[ -n "$cmd" ] || usage
shift

case $cmd in
  build)
    mkdir -p "$work"
    log=$work/$(date +%Y%m%d-%H%M%S)-build.log
    xcodebuild build -project "$project" -scheme WorkoutTracker -destination "platform=iOS Simulator,id=$sim" \
      -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO > "$log" 2>&1 \
      || { grep -E "error:|BUILD FAILED" "$log" | head -20 >&2; echo "build log: $log" >&2; exit 65; }
    echo "built $(app_path)"
    ;;

  launch)
    fixture=${1:-}; [ -n "$fixture" ] || usage; shift
    ensure_axe
    app=$(app_path)
    [ -d "$app" ] || { echo "no built app for $project; run: $0 build" >&2; exit 65; }
    if [ -f "$state_dir/pid" ] && kill -0 "$(cat "$state_dir/pid")" 2>/dev/null; then
      echo "another verification run owns the app on $sim (pid $(cat "$state_dir/pid")); run: $0 stop" >&2
      exit 75
    fi
    read -r -a extra <<< "$(fixture_args "$fixture")"
    args=(-UITEST_FIXTURE ${extra[@]+"${extra[@]}"} -UITEST_DISABLE_ANIMATIONS -UITEST_DISABLE_CELEBRATION_BLOOM "$@")
    xcrun simctl install "$sim" "$app"
    out=$(xcrun simctl launch --terminate-running-process "$sim" "$bundle" "${args[@]}")
    pid=${out##*: }
    mkdir -p "$state_dir"
    printf '%s\n' "$pid" > "$state_dir/pid"
    printf '%s\n' "${args[*]}" > "$state_dir/args"
    for _ in $(seq 1 40); do
      if [ "$(front_pid)" = "$pid" ]; then
        echo "launched $fixture as pid $pid on $sim"
        exit 0
      fi
      sleep 0.25
    done
    echo "pid $pid never became the frontmost accessibility app; run: $0 doctor" >&2
    exit 70
    ;;

  doctor)
    ensure_axe
    rc=0
    xcrun simctl list devices booted | grep -q "$sim" && echo "ok   simulator $sim booted" || { echo "FAIL simulator $sim not booted"; rc=1; }
    app=$(app_path)
    if [ -d "$app" ]; then
      echo "ok   app built $(stat -f %Sm "$app"), HEAD $(git -C "$repo" log -1 --format=%h)"
      stale=$(find "$repo/WorkoutTracker" -name '*.swift' -newer "$app" | head -3)
      [ -z "$stale" ] || { echo "WARN sources newer than the app (run: $0 build):"; echo "$stale" | sed 's/^/     /'; }
    else
      echo "FAIL no built app (run: $0 build)"; rc=1
    fi
    if [ -f "$state_dir/pid" ] && kill -0 "$(cat "$state_dir/pid")" 2>/dev/null; then
      pid=$(cat "$state_dir/pid")
      argv=$(ps -p "$pid" -o args=)
      case $argv in
        *-UITEST_FIXTURE*) echo "ok   pid $pid is ours, running with: $(cat "$state_dir/args")" ;;
        *) echo "FAIL pid $pid is not a fixture launch: $argv"; rc=1 ;;
      esac
      front=$(front_pid)
      [ "$front" = "$pid" ] && echo "ok   accessibility tree answers for pid $pid" || { echo "FAIL frontmost accessibility app is pid $front, not $pid (reboot the simulator if the tree is empty)"; rc=1; }
    else
      echo "FAIL no app launched by this tool on $sim (run: $0 launch <fixture>)"; rc=1
    fi
    exit $rc
    ;;

  tree) ensure_axe; describe | python3 "$tree" flat ;;

  find)
    ensure_axe
    id=${1:-}; [ -n "$id" ] || usage
    describe | python3 "$tree" flat | awk -F'\t' -v id="$id" '$2 == id { print; found = 1 } END { exit !found }'
    ;;

  tap) ensure_axe; "$axe" tap --udid "$sim" --wait-timeout 3 "$@" ;;

  hold)
    ensure_axe
    id=${1:-}; [ -n "$id" ] || usage
    point=$(describe | python3 "$tree" center "$id") || { echo "no element with id $id" >&2; exit 1; }
    read -r x y <<< "$point"
    "$axe" touch --udid "$sim" -x "$x" -y "$y" --down --up --delay "${2:-1.2}"
    ;;

  type) ensure_axe; printf '%s' "${1:-}" | "$axe" type --udid "$sim" --stdin ;;

  swipe)
    ensure_axe
    read -r w h <<< "$(describe | python3 "$tree" frame)"
    x=$((w / 2)); top=$((h * 30 / 100)); bottom=$((h * 80 / 100))
    case ${1:-} in
      up) "$axe" swipe --udid "$sim" --start-x "$x" --start-y "$bottom" --end-x "$x" --end-y "$top" --duration 0.3 ;;
      down) "$axe" swipe --udid "$sim" --start-x "$x" --start-y "$top" --end-x "$x" --end-y "$bottom" --duration 0.3 ;;
      *) usage ;;
    esac
    ;;

  shot)
    ensure_axe
    name=${1:-}; [ -n "$name" ] || usage
    mkdir -p "$evidence"
    "$axe" screenshot --udid "$sim" --output "$evidence/$name.png" >/dev/null 2>&1
    describe | python3 "$tree" flat > "$evidence/$name.tree.txt"
    echo "$evidence/$name.png"
    echo "$evidence/$name.tree.txt"
    ;;

  stop)
    if [ -f "$state_dir/pid" ]; then
      pid=$(cat "$state_dir/pid")
      kill -0 "$pid" 2>/dev/null && xcrun simctl terminate "$sim" "$bundle" && echo "terminated pid $pid"
      rm -rf "$state_dir"
    else
      echo "nothing launched by this tool on $sim"
    fi
    ;;

  axe) ensure_axe; "$axe" "$@" --udid "$sim" ;;

  *) usage ;;
esac
