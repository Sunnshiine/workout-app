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
  tree [--all]                what is on screen, one element per line: role  id  label  value  @x,y wxh
                              --all adds the off-screen ones (scrolled-out rows, picker tails)
  find <id>                   one element by accessibility identifier, on screen or off; exit 1 if absent;
                              says on stderr when it is off-screen, clipped, or disabled
  tap --id ID | --label TEXT | -x X -y Y
                              --id and --label wait up to 3 s (--wait-timeout N) for that element
                              to be enabled, on screen, and with its centre inside every element
                              of nonzero size containing it, then tap that centre; exit 1 and say
                              which it was not. --label is the exact label, a control over a text
                              that shares it; when more than one is left, exit 1 listing each
                              with its centre. -x -y taps the point and reports whatever it hits
  hold <id> [seconds]         long press an element by identifier (default 1.2 s)
  type TEXT                   type into the focused field
  swipe up|down               scroll the screen by half its height
  shot NAME                   NAME.png and NAME.tree.txt into the run, then the tree lines that
                              changed since the previous shot; saves nothing and exits 70 when
                              the PNG is byte-identical to the newest shot's while the tree changed
  diff A B                    the tree lines that changed between two shots of this run, frames ignored
  sheet                       every shot of this run tiled 12 to an image, numbered and labelled; Read each image it prints
  burst NAME [COMMAND...]     12 frames over about 2 s tiled into one image, labelled with their
                              timing; COMMAND is a drive command fired after the first frame, as in
                              burst log-transition tap --id log-active-set-button
  stop                        terminate the app this run launched; the simulator stays up, and it
                              says when the run has shots that are not on a sheet yet. A run
                              launched with Live Activities on is uninstalled, which ends them
  axe ARG...                  raw axe call with --udid filled in
Environment: SIM (simulator UDID, default the booted iPhone 17 Pro, else the newest one, booted for you;
                  launch boots a named one too, and waits for either boot to finish),
             VERIFY_RUN (names the run; give it to launch and every later command remembers it),
             VERIFY_LIVE_ACTIVITIES=1 (launch without -UITEST_DISABLE_LIVE_ACTIVITIES; for
             features/live-activity.md, and its shots carry the activity overlay).
Evidence: .build/verify/evidence/<run>/  (survives stop)
EOF
  exit 2
}

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
tree=$here/tree.py
tiler=$repo/scripts/contact-sheet.swift
. "$repo/scripts/sim-lock.sh"
project=$repo/WorkoutTracker.xcodeproj
bundle=com.sunnypatel.WorkoutTracker
work=$repo/.build/verify
axe=$work/node_modules/xcodebuildmcp/bundled/axe
sim=
sim_state=
state_dir=

pick_sim() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
def version(runtime): return tuple(int(n) for n in runtime.rsplit("iOS-", 1)[-1].split("-"))
devices = [(version(runtime), d) for runtime, ds in json.load(sys.stdin)["devices"].items() for d in ds if d["name"] == "iPhone 17 Pro"]
booted = [d for d in devices if d[1]["state"] == "Booted"]
pick = max(booted or devices, key=lambda pair: pair[0])[1]
print(pick["udid"], pick["state"])'
}

resolve_sim() {
  [ -n "$sim" ] && return 0
  if [ -n "${SIM:-}" ]; then
    sim=$SIM
    sim_state=Booted
  else
    read -r sim sim_state <<< "$(pick_sim)"
  fi
  state_dir=/tmp/workout-verify-$sim
}

need_sim() {
  resolve_sim
  [ "$sim_state" = Booted ] || xcrun simctl boot "$sim"
  sim_state=Booted
}

ensure_axe() {
  [ -x "$axe" ] && return
  echo "installing the accessibility driver into $work (once)" >&2
  mkdir -p "$work"
  npm install --prefix "$work" --no-save --silent --no-audit --no-fund xcodebuildmcp@2.7.0 >/dev/null
  [ -x "$axe" ] || { echo "axe not found after install: $axe" >&2; exit 65; }
}

current_run() {
  if [ -n "${VERIFY_RUN:-}" ]; then printf '%s\n' "$VERIFY_RUN"; return 0; fi
  resolve_sim
  [ -f "$state_dir/run" ] && cat "$state_dir/run"
  return 0
}

begin_run() {
  local name=${VERIFY_RUN:-$(date +%Y%m%d-%H%M%S)}
  mkdir -p "$state_dir"
  printf '%s\n' "$name" > "$state_dir/run"
  printf '%s\n' "$name"
}

run_dir() {
  local name
  name=$(current_run)
  [ -n "$name" ] || name=$(begin_run)
  mkdir -p "$work/evidence/$name"
  printf '%s\n' "$work/evidence/$name"
}

recorded_run_dir() {
  local name
  name=$(current_run)
  if [ -n "$name" ] && [ -d "$work/evidence/$name" ]; then
    printf '%s\n' "$work/evidence/$name"
    return 0
  fi
  echo "no evidence directory for this run; name one: VERIFY_RUN=<run> $0 $cmd ..." >&2
  echo "recent runs:" >&2
  ls -t "$work/evidence" 2>/dev/null | head -3 | sed 's/^/  /' >&2 || true
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

refuse_frozen_frame() {
  local dir=$1 new=$2/$3 name=$3 last changes
  last=$(shot_names "$dir" | tail -1)
  [ -n "$last" ] || return 0
  cmp -s "$dir/$last.png" "$new.png" || return 0
  changes=$(python3 "$tree" diff "$dir/$last.tree.txt" "$new.tree.txt")
  case $changes in "no tree changes "*) return 0 ;; esac
  rm -f "$new.png" "$new.tree.txt"
  {
    echo "refused $name: its frame is byte-identical to $last.png but its tree changed, so the pixels did not move while the tree did"
    printf '%s\n' "$changes"
    echo "if those lines are text the app does not draw, $last.png already shows this screen and the lines are the evidence"
    echo "if not, the shot fired before a transition drew (wait a second and shoot again) or the screenshot pipeline is wedged, as the axe button lock in issue 674 left it, and $last.png may be frozen too (run: xcrun simctl shutdown $sim, then SIM=$sim VERIFY_RUN=${dir##*/} $0 launch <fixture>, and shoot $last again)"
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
[ -z "${VERIFY_RUN:-}" ] || valid_name "$VERIFY_RUN"

case $cmd in
  build)
    need_sim
    mkdir -p "$work"
    log=$work/$(date +%Y%m%d-%H%M%S)-build.log
    xcodebuild build -project "$project" -scheme WorkoutTracker -destination "platform=iOS Simulator,id=$sim" \
      -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO > "$log" 2>&1 \
      || { grep -E "error:|BUILD FAILED" "$log" | head -20 >&2; echo "build log: $log" >&2; exit 65; }
    # An incremental build that produces no new bytes leaves the bundle's mtime alone, and doctor
    # reads that mtime to decide the app is stale. A green build is the claim that it is not.
    touch "$(app_path)"
    echo "built $(app_path)"
    ;;

  launch)
    fixture=${1:-}; [ -n "$fixture" ] || usage; shift
    fixture_flags=$(fixture_args "$fixture")
    resolve_sim
    claim_sim "$sim" "verify.sh launch"
    app=$(app_path)
    [ -d "$app" ] || { echo "no built app for $project; run: $0 build" >&2; exit 65; }
    # bootstatus exits 0 when a shutdown ends the boot.
    without_sim_lock xcrun simctl bootstatus "$sim" -b >/dev/null && xcrun simctl list devices booted | grep -q "$sim" \
      || { echo "simulator $sim did not boot" >&2; exit 70; }
    ensure_axe
    read -r -a extra <<< "$fixture_flags"
    activities=(-UITEST_DISABLE_LIVE_ACTIVITIES)
    [ -z "${VERIFY_LIVE_ACTIVITIES:-}" ] || activities=()
    args=(-UITEST_FIXTURE ${extra[@]+"${extra[@]}"} -UITEST_DISABLE_ANIMATIONS ${activities[@]+"${activities[@]}"} "$@")
    xcrun simctl install "$sim" "$app"
    out=$(xcrun simctl launch --terminate-running-process "$sim" "$bundle" "${args[@]}")
    pid=${out##*: }
    mkdir -p "$state_dir"
    printf '%s\n' "$pid" > "$state_dir/pid"
    printf '%s\n' "${args[*]}" > "$state_dir/args"
    # stop decides whose app it is from this file, so a launch that never comes up still owns its pid.
    begin_run >/dev/null
    for _ in $(seq 1 40); do
      if [ "$(front_pid)" = "$pid" ]; then
        echo "launched $fixture as pid $pid on $sim"
        echo "evidence $(run_dir)"
        exit 0
      fi
      sleep 0.25
    done
    echo "pid $pid never became the frontmost accessibility app; run: $0 doctor" >&2
    exit 70
    ;;

  doctor)
    need_sim
    ensure_axe
    rc=0
    xcrun simctl list devices booted | grep -q "$sim" && echo "ok   simulator $sim booted" || { echo "FAIL simulator $sim not booted"; rc=1; }
    app=$(app_path)
    if [ -d "$app" ]; then
      echo "ok   app built $(stat -f %Sm "$app"), HEAD $(git -C "$repo" log -1 --format=%h)"
      sources=(App Sources/WorkoutTracker WorkoutShared WorkoutWidgets)
      for d in "${sources[@]}"; do
        [ -d "$repo/$d" ] || { echo "FAIL source folder $d is gone, so a stale build can hide; fix the list in $0"; rc=1; }
      done
      # Not just *.swift: Xcode copies every other file in a buildable folder into the bundle too (ADR-0017).
      stale=$(cd "$repo" && find "${sources[@]}" -type f -not -name '.*' -newer "$app" 2>/dev/null | head -3 || true)
      [ -z "$stale" ] || { echo "FAIL sources newer than the app (run: $0 build):"; echo "$stale" | sed 's/^/     /'; rc=1; }
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

  tree)
    need_sim; ensure_axe
    all=${1:-}
    [ -z "$all" ] || [ "$all" = --all ] || usage
    describe | python3 "$tree" flat ${all:+--all}
    ;;

  find)
    need_sim; ensure_axe
    id=${1:-}; [ -n "$id" ] || usage
    describe | python3 "$tree" find "$id"
    ;;

  tap)
    target=(); timeout=3; rest=()
    while [ $# -gt 0 ]; do
      case $1 in
        --id) [ -n "${2:-}" ] && [ ${#target[@]} -eq 0 ] || usage; target=("$2"); shift 2 ;;
        --label) [ -n "${2:-}" ] && [ ${#target[@]} -eq 0 ] || usage; target=(--label "$2"); shift 2 ;;
        --wait-timeout) timeout=${2:-}; [ -n "$timeout" ] || usage; shift 2 ;;
        *) rest+=("$1"); shift ;;
      esac
    done
    if [ ${#target[@]} -gt 0 ]; then
      case $timeout in
        ''|*[!0-9]*) echo "--wait-timeout with --id or --label is whole seconds: $timeout" >&2; exit 2 ;;
      esac
    fi
    need_sim; ensure_axe
    if [ ${#target[@]} -eq 0 ]; then
      "$axe" tap --udid "$sim" --wait-timeout "$timeout" ${rest[@]+"${rest[@]}"}
      exit
    fi
    # axe taps a coordinate and calls that a success, so it cannot tell a tap that landed from one
    # that hit nothing.
    SECONDS=0
    while :; do
      if [ "$SECONDS" -ge "$timeout" ]; then
        point=$(describe | python3 "$tree" tappable "${target[@]}") || exit 1
        break
      fi
      if point=$(describe | python3 "$tree" tappable "${target[@]}" 2>/dev/null); then break; fi
      sleep 0.2
    done
    read -r x y <<< "$point"
    "$axe" tap --udid "$sim" -x "$x" -y "$y" ${rest[@]+"${rest[@]}"}
    ;;

  hold)
    need_sim; ensure_axe
    id=${1:-}; [ -n "$id" ] || usage
    point=$(describe | python3 "$tree" center "$id") || { echo "no element with id $id" >&2; exit 1; }
    read -r x y <<< "$point"
    "$axe" touch --udid "$sim" -x "$x" -y "$y" --down --up --delay "${2:-1.2}"
    ;;

  type) need_sim; ensure_axe; printf '%s' "${1:-}" | "$axe" type --udid "$sim" --stdin ;;

  swipe)
    need_sim; ensure_axe
    read -r w h <<< "$(describe | python3 "$tree" frame)"
    x=$((w / 2)); top=$((h * 30 / 100)); bottom=$((h * 80 / 100))
    case ${1:-} in
      up) "$axe" swipe --udid "$sim" --start-x "$x" --start-y "$bottom" --end-x "$x" --end-y "$top" --duration 0.3 ;;
      down) "$axe" swipe --udid "$sim" --start-x "$x" --start-y "$top" --end-x "$x" --end-y "$bottom" --duration 0.3 ;;
      *) usage ;;
    esac
    ;;

  shot)
    name=${1:-}
    valid_name "$name"
    need_sim; require_sim_free "$sim"; ensure_axe
    dir=$(run_dir)
    pending=$dir/.pending
    mkdir -p "$pending"
    prev=$(shot_names "$dir" | grep -vx -- "$name" | tail -1 || true)
    capture "$pending/$name.png"
    describe | python3 "$tree" flat 2>/dev/null > "$pending/$name.tree.txt"
    if [ ! -s "$pending/$name.png" ] || [ ! -s "$pending/$name.tree.txt" ]; then
      rm -f "$pending/$name.png" "$pending/$name.tree.txt"
      echo "captured nothing for $name; run: $0 doctor" >&2
      exit 70
    fi
    refuse_frozen_frame "$dir" "$pending" "$name"
    mv "$pending/$name.png" "$dir/$name.png"
    mv "$pending/$name.tree.txt" "$dir/$name.tree.txt"
    echo "$dir/$name.png"
    echo "$dir/$name.tree.txt"
    [ -z "$prev" ] || python3 "$tree" diff "$dir/$prev.tree.txt" "$dir/$name.tree.txt"
    ;;

  diff)
    a=${1:-}; b=${2:-}
    { [ -n "$a" ] && [ -n "$b" ]; } || usage
    dir=$(recorded_run_dir)
    for n in "$a" "$b"; do
      [ -f "$dir/$n.tree.txt" ] || { echo "no shot $n in $dir; shots: $(shot_names "$dir" | tr '\n' ' ')" >&2; exit 1; }
    done
    python3 "$tree" diff "$dir/$a.tree.txt" "$dir/$b.tree.txt"
    ;;

  sheet)
    [ $# -eq 0 ] || usage
    dir=$(recorded_run_dir)
    names=$(shot_names "$dir")
    [ -n "$names" ] || { echo "no shots in $dir; take one with: $0 shot NAME" >&2; exit 1; }
    shots=()
    for n in $names; do shots+=("$dir/$n.png"); done
    "$tiler" "$dir/_sheet.png" "${shots[@]}"
    ;;

  burst)
    name=${1:-}
    valid_name "$name"
    shift
    need_sim; require_sim_free "$sim"; ensure_axe
    dir=$(run_dir)
    frames_dir=$dir/$name.burst
    rm -rf "$frames_dir"
    rm -f "$dir/$name.burst.png"
    mkdir -p "$frames_dir"
    capture "$frames_dir/f00.png"
    if [ $# -gt 0 ]; then
      SIM=$sim "$0" "$@" >/dev/null || { rm -rf "$frames_dir"; exit 1; }
    fi
    touch "$frames_dir/.drive-returned"
    for i in 01 02 03 04 05 06 07 08 09 10 11; do capture "$frames_dir/f$i.png"; done
    frames=$(python3 "$here/frames.py" "$frames_dir")
    paths=()
    while IFS= read -r frame; do paths+=("$frame"); done <<< "$frames"
    "$tiler" "$dir/$name.burst.png" "${paths[@]}"
    ;;

  stop)
    need_sim
    if [ -f "$state_dir/pid" ]; then
      pid=$(cat "$state_dir/pid")
      alive=
      uninstall=
      if kill -0 "$pid" 2>/dev/null; then alive=1; fi
      # A Live Activity belongs to the app, not to its process, so terminating leaves it on the
      # springboard over every later shot. Uninstalling is the only lever on one from outside the
      # app, and the next launch reinstalls anyway. A state dir with no args file cannot say which
      # run this was, and uninstalling is the destructive guess, so it keeps the old behaviour.
      if [ -f "$state_dir/args" ] && ! grep -q -- -UITEST_DISABLE_LIVE_ACTIVITIES "$state_dir/args"; then uninstall=1; fi
      owner=
      [ -f "$state_dir/run" ] && owner=$(cat "$state_dir/run")
      if [ -n "$alive$uninstall" ] && [ -n "$owner" ] && [ -n "${VERIFY_RUN:-}" ] && [ "$owner" != "$VERIFY_RUN" ]; then
        echo "the app on $sim belongs to run $owner, not to $VERIFY_RUN; to stop it anyway, run: VERIFY_RUN=$owner $0 stop" >&2
        exit 75
      fi
      [ -z "$uninstall" ] || require_sim_free "$sim"
      if [ -n "$alive" ]; then
        xcrun simctl terminate "$sim" "$bundle"
        echo "terminated pid $pid"
      fi
      if [ -n "$uninstall" ]; then
        if xcrun simctl uninstall "$sim" "$bundle"; then
          echo "uninstalled the app, ending any Live Activity this run started"
        else
          echo "could not uninstall on $sim, so a Live Activity this run started may still be on it; end it with: xcrun simctl uninstall $sim $bundle" >&2
        fi
      fi
      rm -f "$state_dir/pid" "$state_dir/args"
    else
      echo "nothing launched by this tool on $sim"
    fi
    dir=$(recorded_run_dir 2>/dev/null) || exit 0
    sheet=$dir/_sheet.png
    # bash 3.2, the stock macOS shell, compares [ -nt ] in whole seconds. find -newer compares nanoseconds.
    if [ -f "$sheet" ]; then
      pending=$(find "$dir" -maxdepth 1 -name '*.tree.txt' -newer "$sheet" | wc -l | tr -d ' ')
    else
      pending=$(shot_names "$dir" | wc -l | tr -d ' ')
    fi
    [ "$pending" -eq 0 ] || echo "shots in $(basename "$dir") not on a contact sheet yet: $pending; run: $0 sheet, then Read every image it prints"
    ;;

  axe) need_sim; ensure_axe; "$axe" "$@" --udid "$sim" ;;

  *) usage ;;
esac
