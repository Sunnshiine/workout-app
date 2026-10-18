# shellcheck shell=bash
# Sourced by verify.sh: refusals, install, launch, ownership of the app, the keyboard preference, and doctor.

last_run_named() { [ -f "$state_dir/run" ] && [ ! -f "$state_dir/unnamed" ]; }

record_refusal() {
  local run
  echo "$1" >&2
  [ "$cmd" = launch ] || return 0
  mkdir -p "$state_dir"
  run=${VERIFY_RUN:-}
  if [ -z "$run" ]; then
    if last_run_named; then return 0; fi
    run=$(current_run)
    [ -n "$run" ] || run=$(begin_run)
  fi
  printf '%s\n' "$1" > "$state_dir/refused.$run"
  printf '%s %s refused: %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$cmd" "$1" >> "$(run_dir)/launches.txt"
}

refuse() {
  trap end_claim EXIT
  record_refusal "$1"
  exit "$2"
}

report_unchanged() {
  local rc=$?
  end_claim
  [ $rc -ne 0 ] || return 0
  record_refusal "app on $sim unchanged: $(installed_line); this $cmd wanted $wanted_line"
}

relaunches_the_run_that_owns_sim() { [ -n "${VERIFY_RUN:-}" ] && [ "$VERIFY_RUN" = "$(cat "$state_dir/run" 2>/dev/null)" ]; }

claim_for_install() {
  resolve_sim
  [ -z "$at" ] || at=$(resolve_commit "$at")
  sim_available "$sim" || exit
  wanted_line="${at:0:8} from the app cache"
  trap report_unchanged EXIT
  target_app
  if [ "$cmd" = launch ] && [ -z "$at" ] && relaunches_the_run_that_owns_sim; then refuse_replacing_cache; fi
  claim_sim "$sim" "verify.sh $cmd"
  wait_for_boot
}

wait_for_boot() {
  # bootstatus exits 0 when a shutdown ends the boot.
  without_sim_lock xcrun simctl bootstatus "$sim" -b >/dev/null && booted \
    || { echo "simulator $sim did not boot" >&2; exit 70; }
}

refuse_replacing_cache() {
  local installed hash commit dirty origin
  installed=$(installed_app)
  [ -n "$installed" ] || return 0
  read -r hash commit dirty origin <<< "$(identity_of "$installed")"
  { [ "$origin" = cache ] && [ "$hash" != "$want_hash" ]; } || return 0
  refuse "$sim holds $(identity_line "$hash" "$commit" "$dirty" "$origin"), and this launch would replace it with $wanted_line. To run the cached build: launch --at ${commit:0:8}${animated:+ --animated} $fixture. To replace it: install, then launch." 65
}

simctl_install() {
  xcrun simctl install "$sim" "$app" || refuse "simctl install failed, so $sim holds $(installed_line), not $wanted_line" 70
}

holds_wanted() {
  local installed
  installed=$(installed_app)
  [ -n "$installed" ] && [ "$(app_hash "$installed")" = "$want_hash" ]
}

install_app() {
  simctl_install
  if ! holds_wanted; then
    # simctl install over an installed app has left the old bytes in place; an uninstall first clears it.
    echo "after simctl install, $sim holds $(installed_line), not $wanted_line; uninstalling it and installing once more" >&2
    xcrun simctl uninstall "$sim" "$bundle" || true
    simctl_install
    holds_wanted || refuse "after simctl install, $sim holds $(installed_line), not $wanted_line that this $cmd installed from $app" 70
  fi
  trap end_claim EXIT
}

launch_parse() {
  at=
  animated=
  while [ $# -gt 0 ]; do
    case $1 in
      --at) [ -n "${2:-}" ] || usage; at=$2; shift 2 ;;
      --animated) animated=1; shift ;;
      *) break ;;
    esac
  done
  fixture=${1:-}; [ -n "$fixture" ] || usage; shift
  fixture_flags=$(fixture_args "$fixture")
  passthrough=("$@")
  for arg in "$@"; do
    [ "$arg" != --at ] || { echo "--at goes before the fixture: launch --at COMMIT $fixture" >&2; exit 2; }
    [ "$arg" != --animated ] || { echo "--animated goes before the fixture: launch --animated $fixture" >&2; exit 2; }
  done
}

launch_args() {
  local extra motion activities
  read -r -a extra <<< "$fixture_flags"
  motion=(-UITEST_DISABLE_ANIMATIONS)
  [ -z "$animated" ] || motion=()
  activities=(-UITEST_DISABLE_LIVE_ACTIVITIES)
  [ -z "${VERIFY_LIVE_ACTIVITIES:-}" ] || activities=()
  args=(-UITEST_FIXTURE ${extra[@]+"${extra[@]}"} ${motion[@]+"${motion[@]}"} ${activities[@]+"${activities[@]}"} ${passthrough[@]+"${passthrough[@]}"})
}

start_app() {
  local out
  out=$(xcrun simctl launch --terminate-running-process "$sim" "$bundle" "${args[@]}")
  pid=${out##*: }
  mkdir -p "$state_dir"
  printf '%s\n' "$pid" > "$state_dir/pid"
  printf '%s\n' "${args[*]}" > "$state_dir/args"
  # stop decides whose app it is from this file, so a launch that never comes up still owns its pid.
  run=$(begin_run)
}

record_launch() {
  printf '%s %s %s on %s from %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$fixture${animated:+ animated}" "$launched_line" "$sim" "$repo" \
    >> "$(run_dir)/launches.txt"
}

await_front() {
  for _ in $(seq 1 40); do
    if [ "$(front_pid)" = "$pid" ]; then
      rm -f "$state_dir/refused.$run"
      echo "launched $fixture as pid $pid on $sim${animated:+ (animations on)}"
      echo "$launched_line"
      echo "evidence $(run_dir)"
      exit 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "pid $pid exited during launch" >&2
      # simctl launch --stderr captures nothing on iOS 27, so a fatalError's message is read back from the log.
      xcrun simctl spawn "$sim" log show --last 1m --style compact \
        --predicate "processID == $pid AND senderImagePath ENDSWITH \"libswiftCore.dylib\"" 2>/dev/null \
        | sed -n 's/^.*(libswiftCore.dylib) //p' >&2 || true
      exit 70
    fi
    sleep 0.25
  done
  echo "pid $pid never became the frontmost accessibility app; run: $0 doctor" >&2
  exit 70
}

refuse_another_runs_app() {
  local owner pid
  [ -n "${VERIFY_RUN:-}" ] || return 0
  owner=$(cat "$state_dir/run" 2>/dev/null) || return 0
  [ "$owner" != "$VERIFY_RUN" ] || return 0
  pid=$(cat "$state_dir/pid" 2>/dev/null) || return 0
  is_fixture_launch "$pid" || return 0
  echo "the app on $sim belongs to run $owner (pid $pid), not to $VERIFY_RUN, so this would drive another run's app; launch yours first: SIM=$sim VERIFY_RUN=$VERIFY_RUN $0 $relaunch" >&2
  exit 75
}

require_own_app() {
  local run again
  require_lease "$sim"
  refuse_another_runs_app
  run=$(current_run)
  [ -n "$run" ] && [ -f "$state_dir/refused.$run" ] || return 0
  again="SIM=$sim${VERIFY_RUN:+ VERIFY_RUN=$run} $0"
  echo "the last launch of run $run on $sim was refused, so this would drive whatever that refusal left running ($(cat "$state_dir/refused.$run")); stop it, then launch again: $again stop, then $again $relaunch" >&2
  exit 75
}

keyboard_minimized() {
  [ "$(xcrun simctl spawn "$sim" defaults read com.apple.keyboard.preferences AutomaticMinimizationEnabled 2>/dev/null)" = 1 ]
}

show_keyboard() { xcrun simctl spawn "$sim" defaults write com.apple.keyboard.preferences AutomaticMinimizationEnabled -bool false; }

reset_minimized_keyboard() {
  keyboard_minimized || return 0
  if show_keyboard; then
    echo "AutomaticMinimizationEnabled was 1 on $sim, which hides the software keyboard (issue 700); this launch reset it to 0" >&2
  else
    echo "AutomaticMinimizationEnabled is 1 on $sim, which hides the software keyboard (issue 700), and resetting it failed" >&2
  fi
}

decimal() {
  case $1 in ''|.|*[!0-9.]*|*.*.*) return 1 ;; esac
}

keep_video_then_stamp() {
  mv "$1/$3.mp4" "$2/$3.mp4"
  mv "$1/$3.take" "$2/$3.take"
  mv "$1/$3.end.txt" "$2/$3.end.txt"
  rmdir "$1" 2>/dev/null || true
}

reset_keyboard() {
  if show_keyboard; then
    echo "AXe keyboard input hides the software keyboard in this app until its next launch (issue 700); the preference that would keep it hidden after that is reset" >&2
  else
    echo "AXe keyboard input hides the software keyboard in this app until its next launch (issue 700), and resetting the preference that keeps it hidden after that failed" >&2
  fi
}

sources_newer() {
  local d stale rc=0
  for d in "${inputs[@]}"; do
    [ -e "$repo/$d" ] || { echo "FAIL source $d is gone, so a stale build can hide; fix the list in $0"; rc=1; }
  done
  # Not just *.swift: Xcode copies every other file in a buildable folder into the bundle too (ADR-0017).
  stale=$(cd "$repo" && find "${inputs[@]}" -type f -not -name '.*' -not -path '*/xcuserdata/*' -newer "$1" 2>/dev/null | head -3 || true)
  [ -z "$stale" ] || { echo "FAIL sources newer than the app (run: $0 build):"; echo "$stale" | sed 's/^/     /'; rc=1; }
  return $rc
}

doctor_app() {
  local installed hash commit dirty origin cached
  load_worktree_build
  installed=$(installed_app)
  if [ -z "$installed" ]; then
    booted || { echo "FAIL installed app unknown, because $sim is not booted (run: $0 launch <fixture>)"; return 1; }
    echo "FAIL nothing installed on $sim (run: $0 launch <fixture>)"
    [ -n "$built" ] || echo "FAIL no built app (run: $0 build)"
    return 1
  fi
  read -r hash commit dirty origin <<< "$(identity_of "$installed")"
  if [ "$origin" = cache ]; then
    cached=$(cached_app_path "$commit")
    if [ -d "$cached" ] && [ "$(app_hash "$cached")" = "$hash" ]; then
      echo "ok   installed $(identity_line "$hash" "$commit" "$dirty" "$origin"); $(worktree_build_note)"
      return 0
    fi
  fi
  [ -n "$built" ] || { echo "FAIL no built app (run: $0 build)"; return 1; }
  if [ "$hash" != "$built_hash" ]; then
    echo "FAIL installed $(identity_line "$hash" "$commit" "$dirty" "$origin") is not this worktree's build, $(short_identity "$built_hash" "$built_commit" "$built_dirty") (run: $0 install)"
    return 1
  fi
  echo "ok   installed $(identity_line "$hash" "$commit" "$dirty" "$origin")"
  sources_newer "$built"
}
