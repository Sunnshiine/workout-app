#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
tree=$here/tree.py
tiler=$repo/scripts/contact-sheet.swift
. "$repo/scripts/sim-lock.sh"
host_knob WORKOUT_LOAD_LIMIT 50 1
project=$repo/WorkoutTracker.xcodeproj
bundle=com.sunnypatel.WorkoutTracker
work=$repo/.build/verify
axe=$work/node_modules/xcodebuildmcp/bundled/axe
stamp_name=verify-stamp
sources=(App Sources/WorkoutTracker WorkoutShared WorkoutWidgets)
inputs=("${sources[@]}" WorkoutTracker.xcodeproj Package.swift Package.resolved)
sim=
state_dir=
built_hash=
built_loaded=

. "$here/verify-usage.sh"
. "$here/verify-runs.sh"
. "$here/verify-builds.sh"
. "$here/verify-launch.sh"

cmd=${1:-}
[ -n "$cmd" ] || usage
shift
relaunch="launch <fixture>"
[ -z "${VERIFY_RUN:-}" ] || valid_name "$VERIFY_RUN"

case $cmd in
  build)
    resolve_sim
    sim_available "$sim" || exit
    commit=$(git -C "$repo" rev-parse HEAD)
    changes=$(git -C "$repo" status --porcelain -- "${inputs[@]}")
    xcodebuild_build "$project" "" "$work/$(date +%Y%m%d-%H%M%S)-build.log" || exit
    app=$(app_path)
    # An incremental build that produces no new bytes leaves the bundle's mtime alone, and doctor
    # reads that mtime to decide the app is stale. A green build is the claim that it is not.
    touch "$app"
    dirty=0
    [ -z "$changes" ] || dirty=1
    write_stamp "$app" "$commit" "$dirty" "$repo"
    echo "built $app"
    app_line "$app"
    ;;

  install)
    [ $# -le 1 ] || usage
    at=${1:-}
    claim_for_install
    replaced=$(installed_app)
    [ -z "$replaced" ] || [ "$(app_hash "$replaced")" != "$want_hash" ] || replaced=
    [ -z "$replaced" ] || replaced=$(app_line "$replaced")
    install_app
    [ -z "$replaced" ] || echo "replaced $replaced"
    echo "$wanted_line"
    ;;

  launch)
    launch_parse "$@"
    claim_for_install
    ensure_axe
    [ -n "$at" ] || refuse_replacing_cache
    install_app
    reset_minimized_keyboard
    launch_args
    start_app
    record_launch
    await_front
    ;;

  doctor)
    resolve_sim; require_lease "$sim"
    ensure_axe
    rc=0
    booted && echo "ok   simulator $sim booted" || { echo "FAIL simulator $sim not booted"; rc=1; }
    doctor_app || rc=1
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
    if booted; then
      if keyboard_minimized; then
        echo "FAIL AutomaticMinimizationEnabled is 1 on $sim, so a focused field shows no software keyboard (issue 700); the next launch resets it (run: $0 launch <fixture>)"
        rc=1
      else
        echo "ok   AutomaticMinimizationEnabled is not 1 on $sim"
      fi
    fi
    exit $rc
    ;;

  tree)
    resolve_sim; require_lease "$sim"; ensure_axe
    all=${1:-}
    [ -z "$all" ] || [ "$all" = --all ] || usage
    describe | python3 "$tree" flat ${all:+--all}
    ;;

  find)
    resolve_sim; require_lease "$sim"; ensure_axe
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
    resolve_sim; require_own_app; ensure_axe
    if [ ${#target[@]} -eq 0 ]; then
      "$axe" tap --udid "$sim" --wait-timeout "$timeout" ${rest[@]+"${rest[@]}"}
      exit
    fi
    app_pid=$(cat "$state_dir/pid" 2>/dev/null || true)
    lands() {
      local screen resolved front
      unchecked=
      screen=$(describe) || return 1
      resolved=$(python3 "$tree" tappable "${target[@]}" <<< "$screen") || return 1
      front=$(python3 "$tree" pid <<< "$screen")
      read -r x y <<< "$resolved"
      # axe's point read on the Home Screen can name a neighbouring icon instead of the one tapped.
      if [ -n "$app_pid" ] && [ "$front" != "$app_pid" ]; then
        unchecked="not checked for cover: pid $front is in front, not pid $app_pid that launch started, so this tap goes by the tree alone"
        return
      fi
      "$axe" describe-ui --udid "$sim" --point "$x,$y" \
        | python3 "$tree" landing "${resolved#*$'\n'}" "$front" "$x" "$y"
    }
    SECONDS=0
    while :; do
      if [ "$SECONDS" -ge "$timeout" ]; then lands || exit 1; break; fi
      if lands 2>/dev/null; then break; fi
      sleep 0.2
    done
    [ -z "$unchecked" ] || echo "$unchecked" >&2
    "$axe" tap --udid "$sim" -x "$x" -y "$y" ${rest[@]+"${rest[@]}"}
    ;;

  hold)
    resolve_sim; require_own_app; ensure_axe
    id=${1:-}; [ -n "$id" ] || usage
    point=$(describe | python3 "$tree" center "$id") || { echo "no element with id $id" >&2; exit 1; }
    read -r x y <<< "$point"
    "$axe" touch --udid "$sim" -x "$x" -y "$y" --down --up --delay "${2:-1.2}"
    ;;

  type)
    resolve_sim; require_own_app; ensure_axe
    rc=0
    printf '%s' "${1:-}" | "$axe" type --udid "$sim" --stdin || rc=$?
    reset_keyboard
    exit $rc
    ;;

  swipe)
    resolve_sim; require_own_app; ensure_axe
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
    resolve_sim; require_sim_free "$sim"; require_own_app; ensure_axe
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
    refuse_unmoved_frame "$dir" "$pending" "$name"
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

  crop)
    shot=${1:-}
    valid_name "$shot"
    shift
    { [ $# -eq 1 ] || [ $# -eq 4 ]; } || usage
    dir=$(recorded_run_dir)
    [ -f "$dir/$shot.png" ] && [ -f "$dir/$shot.tree.txt" ] \
      || { echo "no shot $shot in $dir; shots: $(shot_names "$dir" | tr '\n' ' ')" >&2; exit 1; }
    width=$(sips -g pixelWidth "$dir/$shot.png" | awk '/pixelWidth:/ { print $2 }')
    region=$(python3 "$tree" crop "$dir/$shot.tree.txt" "$width" "$@") || exit
    read -r px py pw ph rect <<< "$region"
    out=$dir/$shot-crop-$rect.png
    "$tiler" --crop "$px,$py,$pw,$ph" "$out" "$dir/$shot.png"
    printf '%s\t%sx%s\n' "$out" "$pw" "$ph"
    ;;

  burst)
    name=${1:-}
    valid_name "$name"
    shift
    resolve_sim; require_sim_free "$sim"; require_own_app; ensure_axe
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

  record)
    name=${1:-}
    valid_name "$name"
    shift
    tail=2
    if [ "${1:-}" = --tail ]; then
      [ $# -ge 2 ] || usage
      tail=$2
      shift 2
    fi
    if [ $# -gt 0 ]; then
      [ "$1" = -- ] || usage
      shift
    fi
    decimal "$tail" || usage
    resolve_sim
    command -v ffprobe >/dev/null || { echo "record reads its video with ffprobe; install it: brew install ffmpeg" >&2; exit 70; }
    [ "${1:-}" != launch ] || relaunch="$*"
    require_sim_free "$sim"; require_own_app
    wait_until_clear "the load to fall to $WORKOUT_LOAD_LIMIT before recording" \
      load_clear "$WORKOUT_LOAD_LIMIT"
    require_sim_free "$sim"; require_own_app; ensure_axe
    dir=$(run_dir)
    pending=$dir/.pending
    mkdir -p "$pending"
    rm -f "$pending/$name.mp4" "$pending/$name.take" "$pending/$name.end.txt"
    rc=0
    python3 "$here/take.py" record --sim "$sim" --run "${dir##*/}" --verify "$0" --out "$pending/$name.mp4" \
      --tail "$tail" --limit "$WORKOUT_LOAD_LIMIT" -- "$@" > "$pending/$name.take" || rc=$?
    if [ $rc -ne 0 ] && [ $rc -ne 3 ]; then
      rm -f "$pending/$name.mp4" "$pending/$name.take"
      exit $rc
    fi
    if ! ui=$(describe) || ! screen=$(printf '%s\n' "$ui" | python3 "$tree" frame); then
      rm -f "$pending/$name.mp4" "$pending/$name.take"
      echo "could not read the screen's size in points after the take, so $name.take cannot be scaled; run: $0 doctor" >&2
      exit 70
    fi
    if ! card_pt=$(printf '%s\n' "$ui" | python3 "$tree" frame-of active-set-card); then
      rm -f "$pending/$name.mp4" "$pending/$name.take"
      echo "could not read active-set-card's frame from the accessibility tree after the take," \
        "so $name.take cannot say where the card is; run: $0 doctor" >&2
      exit 70
    fi
    printf '%s\n' "$ui" | python3 "$tree" flat > "$pending/$name.end.txt" 2>/dev/null
    animations=unknown
    if [ -f "$state_dir/args" ]; then
      animations=on
      if grep -q -- -UITEST_DISABLE_ANIMATIONS "$state_dir/args"; then animations=off; fi
    fi
    printf 'screen_pt=%s\ncard_pt=%s\nanimations=%s\napp=%s\n' "${screen/ /x}" "$card_pt" "$animations" \
      "$(installed_line)" >> "$pending/$name.take"
    keep_video_then_stamp "$pending" "$dir" "$name"
    echo "$dir/$name.mp4"
    echo "$dir/$name.take"
    echo "$dir/$name.end.txt"
    python3 "$here/take.py" summary "$dir/$name.take"
    exit $rc
    ;;

  stop)
    resolve_sim; require_lease "$sim"
    if [ -f "$state_dir/pid" ]; then
      pid=$(cat "$state_dir/pid")
      alive=
      uninstall=
      # A pid alone can name another process once the app is gone, since pids wrap fast on a build
      # machine. Terminating by bundle id then exits 3, or ends a copy of the app a UI test owns (#728).
      if is_fixture_launch "$pid"; then alive=1; fi
      # A Live Activity belongs to the app, not to its process, so terminating leaves it on the
      # springboard over every later shot. Uninstalling is the only lever on one from outside the
      # app, and the next launch reinstalls anyway. A state dir with no args file cannot say which
      # run this was, and uninstalling is the destructive guess, so it keeps the old behaviour.
      if launched_with_live_activities "$state_dir"; then uninstall=1; fi
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

  axe)
    resolve_sim; require_own_app; ensure_axe
    rc=0
    "$axe" "$@" --udid "$sim" || rc=$?
    case ${1:-} in key|key-sequence|key-combo|type) reset_keyboard ;; esac
    exit $rc
    ;;

  *) usage ;;
esac
