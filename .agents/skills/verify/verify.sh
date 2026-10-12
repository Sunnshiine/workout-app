#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: .agents/skills/verify/verify.sh <command> [args]
  build                       build this worktree's app for SIM and stamp it with its commit (rerun after
                              any source change)
  install [COMMIT]            install this worktree's build, or COMMIT's build from the app cache every
                              worktree of this repo shares (built once, on first use); prints the app now
                              installed, and the one it replaced
  launch [--at COMMIT] [--animated] <fixture> [ARG...]
                              install and launch into a fixture (extra -UITEST_* ARGs pass through); prints
                              the app's hash and the commit it was built from. Without --at it installs
                              this worktree's build and refuses to replace an installed cached build;
                              --at COMMIT runs COMMIT's cached build; --animated leaves SwiftUI and UIKit
                              motion on (no -UITEST_DISABLE_ANIMATIONS)
                              fixtures: session settings onboarding long-session partial-block
                                        completed-open-exercises developer-tools
  doctor                      read-only: is the installed app this worktree's build or a cached one, and is
                              the running instance ours, current, and answering?
  tree [--all]                what is on screen, one element per line: role  id  label  value  @x,y wxh
                              --all adds the off-screen ones (scrolled-out rows, picker tails) and
                              the ones with neither id nor label, by role, value and frame
  find <id>                   one element by accessibility identifier, on screen or off; exit 1 if absent;
                              says on stderr when it is off-screen, clipped, or disabled
  tap --id ID | --label TEXT | -x X -y Y
                              --id and --label wait up to 3 s (--wait-timeout N) for that element
                              to be enabled, on screen, with its centre inside every element of
                              nonzero size containing it, and on top at that centre, then tap the
                              centre; exit 1 and say which it was not (off-screen, clipped,
                              disabled, covered). --label is the exact label, a control over a text
                              that shares it; when more than one is left, exit 1 listing each
                              with its centre. -x -y taps the point and reports whatever it hits
  hold <id> [seconds]         long press an element by identifier (default 1.2 s)
  type TEXT                   type into the focused field, then reset the keyboard preference AXe
                              input sets (issue 700)
  swipe up|down               scroll the screen by half its height
  shot NAME                   NAME.png and NAME.tree.txt into the run, then the tree lines that
                              changed since the previous shot; saves nothing and exits 70 when
                              the PNG is byte-identical to the newest shot's while the tree changed
  diff A B                    the tree lines that changed between two shots of this run, frames ignored
  sheet                       every shot of this run tiled 12 to an image, numbered and labelled; Read each image it prints
  crop SHOT ID | crop SHOT X Y W H
                              SHOT-crop-X_Y_WxH.png at the shot's own pixels: ID's frame on that shot
                              with 8 points around it, or that rect in tree points, clipped to the
                              screen; prints its path and pixel size. Not a shot, so sheet, diff,
                              and stop never see it
  burst NAME [COMMAND...]     12 frames over about 2 s tiled into one image, labelled with their
                              timing; COMMAND is a drive command fired after the first frame, as in
                              burst log-transition tap --id log-active-set-button
  stop                        terminate the app this run launched; the simulator stays up, and it
                              says when the run has shots that are not on a sheet yet. A run
                              launched with Live Activities on is uninstalled, which ends them
  axe ARG...                  raw axe call with --udid filled in; after a keyboard verb, the same
                              keyboard preference reset as type
Environment: SIM (the UDID of your own simulator, required by every command that touches one; launch
                  boots it and waits for the boot to finish),
             VERIFY_RUN (names the run; give it to launch and every later command remembers it.
                  tap, hold, type, swipe, shot, burst and axe refuse while another run's app is
                  alive on SIM, and after this run's launch was refused until one succeeds),
             VERIFY_EVIDENCE (the parent of the run directories; default
                  <main checkout>/.claude/work/evidence/<branch>),
             VERIFY_LIVE_ACTIVITIES=1 (launch without -UITEST_DISABLE_LIVE_ACTIVITIES; for
             features/live-activity.md, and its shots carry the activity overlay).
Evidence: <VERIFY_EVIDENCE>/<run>/ survives stop and worktree removal; its launches.txt names the
          app each launch ran.
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
stamp_name=verify-stamp
sources=(App Sources/WorkoutTracker WorkoutShared WorkoutWidgets)
inputs=("${sources[@]}" WorkoutTracker.xcodeproj Package.swift Package.resolved)
sim=
state_dir=
built_hash=
built_loaded=

resolve_sim() {
  [ -n "$sim" ] && return 0
  if [ -z "${SIM:-}" ]; then
    cat >&2 <<'EOF'
SIM is not set. verify.sh drives only the simulator you name, because the stock iPhone 17 Pro is shared and another agent's app may be on it (issue 660).
Make a lane simulator once and pass it on every call:
  export SIM=$(xcrun simctl create lane-<name> "iPhone 17 Pro" com.apple.CoreSimulator.SimRuntime.iOS-27-0)
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
  mkdir -p "$state_dir"
  printf '%s\n' "$name" > "$state_dir/run"
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

app_hash() {
  (cd "$1" && find . -type f ! -name "$stamp_name" -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256) \
    | shasum -a 256 | cut -c1-64
}

stamp_field() { sed -n "s/^$2=//p" "$1"; }

write_stamp() {
  local hash
  hash=$(app_hash "$1")
  printf 'commit=%s\ndirty=%s\norigin=%s\ncode_sha256=%s\n' "$2" "$3" "$4" "$hash" > "$1/$stamp_name"
}

stamp_vouches() {
  local app=$1 hash=$2
  [ -f "$app/$stamp_name" ] && [ "$(stamp_field "$app/$stamp_name" code_sha256)" = "$hash" ]
}

identity_of() {
  local stamp=$1/$stamp_name hash
  hash=$(app_hash "$1")
  if stamp_vouches "$1" "$hash"; then
    printf '%s %s %s %s\n' "$hash" "$(stamp_field "$stamp" commit)" "$(stamp_field "$stamp" dirty)" "$(stamp_field "$stamp" origin)"
  else
    printf '%s - 0 -\n' "$hash"
  fi
}

short_identity() {
  local dirty=
  if [ "$2" = - ]; then printf 'app %s commit unknown\n' "${1:0:12}"; return 0; fi
  [ "$3" != 1 ] || dirty=-dirty
  printf 'app %s commit %s%s\n' "${1:0:12}" "${2:0:8}" "$dirty"
}

identity_line() {
  local where
  case $4 in
    -) printf '%s (not built by verify.sh)\n' "$(short_identity "$1" "$2" "$3")"; return 0 ;;
    cache) where="cached build" ;;
    "$repo")
      where="this worktree's build"
      [ -n "$built_loaded" ] || load_worktree_build
      [ -z "$built_hash" ] || [ "$built_hash" = "$1" ] || where="an earlier build of this worktree"
      ;;
    *) where="built in $4" ;;
  esac
  printf '%s (%s)\n' "$(short_identity "$1" "$2" "$3")" "$where"
}

app_line() {
  local hash commit dirty origin
  read -r hash commit dirty origin <<< "$(identity_of "$1")"
  identity_line "$hash" "$commit" "$dirty" "$origin"
}

installed_app() { xcrun simctl get_app_container "$sim" "$bundle" 2>/dev/null || true; }
booted() { xcrun simctl list devices booted | grep -q "$sim"; }

installed_line() {
  local installed
  installed=$(installed_app)
  if [ -n "$installed" ]; then app_line "$installed"
  elif booted; then echo "nothing installed"
  else echo "an unknown app (the simulator is not booted)"
  fi
}

load_worktree_build() {
  built_loaded=1
  built=$(app_path)
  built_hash=''
  built_commit=-
  built_dirty=0
  [ -d "$built" ] || { built=; return 0; }
  read -r built_hash built_commit built_dirty _ <<< "$(identity_of "$built")"
}

worktree_build_note() {
  if [ -n "$built" ]; then
    echo "this worktree's build is $(short_identity "$built_hash" "$built_commit" "$built_dirty")"
  else
    echo "this worktree has no build"
  fi
}

xcodebuild_build() {
  local derived=()
  [ -z "$2" ] || derived=(-derivedDataPath "$2")
  mkdir -p "$(dirname "$3")"
  xcodebuild build -project "$1" -scheme WorkoutTracker -destination "platform=iOS Simulator,id=$sim" \
    ${derived[@]+"${derived[@]}"} -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO > "$3" 2>&1 \
    || { grep -E "error:|BUILD FAILED" "$3" | head -20 >&2; echo "build log: $3" >&2; return 65; }
}

cache_root() { printf '%s/.claude/work/app-cache\n' "$(main_root)"; }

resolve_commit() {
  git -C "$repo" rev-parse --verify --quiet "$1^{commit}" \
    || { echo "$1 names no single commit in this repo (unknown or ambiguous)" >&2; exit 2; }
}

cache_hit() { [ -d "$1" ] && stamp_vouches "$1" "$(app_hash "$1")"; }

drop_cache_scratch() {
  rm -rf "$1"
  git -C "$repo" worktree prune
}

try_lock() { python3 -c 'import fcntl, sys; fcntl.flock(int(sys.argv[1]), fcntl.LOCK_EX | fcntl.LOCK_NB)' "$1" 2>/dev/null; }

sweep_cache_scratch() {
  local root=$1 locked_sha=$2 dir sha
  for dir in "$root"/*.build "$root"/*.tmp; do
    [ -e "$dir" ] || continue
    sha=${dir##*/}
    sha=${sha%.*}
    [ "$sha" != "$locked_sha" ] || continue
    (exec 7>>"$root/$sha.lock" && try_lock 7 && rm -rf "$dir") || true
  done
  git -C "$repo" worktree prune
}

scratch_checkout() {
  if [ ! -f "$1/src/.git" ] || [ "$(git -C "$1/src" rev-parse HEAD 2>/dev/null)" != "$2" ]; then
    drop_cache_scratch "$1"
    git -C "$repo" worktree add --force --force --quiet --detach "$1/src" "$2" >&2
  fi
  "$repo/scripts/bootstrap-xcode-worktree.sh" "$1/src"
}

cached_app_path() { printf '%s/%s/WorkoutTracker.app\n' "$(cache_root)" "$1"; }

ensure_cached() {
  local sha=$1 root app lock scratch tmp
  root=$(cache_root)
  app=$(cached_app_path "$sha")
  cache_hit "$app" && return 0
  mkdir -p "$root/logs"
  lock=$root/$sha.lock
  # xcodebuild inherits fd 8, so the build of a killed install keeps the lock until it exits.
  exec 8>>"$lock"
  python3 -c 'import fcntl, sys
try: fcntl.flock(8, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    print(sys.argv[1], file=sys.stderr, flush=True)
    fcntl.flock(8, fcntl.LOCK_EX)' "waiting for another build of ${sha:0:8} into the app cache (lsof $lock lists it)"
  if cache_hit "$app"; then exec 8>&-; return 0; fi
  scratch=$root/$sha.build
  tmp=$root/$sha.tmp
  sweep_cache_scratch "$root" "$sha"
  rm -rf "$tmp" "${root:?}/$sha"
  echo "building ${sha:0:8} into the app cache at $root (under a minute to a few; give the call a 10 min timeout)" >&2
  scratch_checkout "$scratch" "$sha"
  if ! xcodebuild_build "$scratch/src/WorkoutTracker.xcodeproj" "$scratch/dd" "$root/logs/$sha.log"; then
    drop_cache_scratch "$scratch"
    exit 65
  fi
  mkdir -p "$tmp"
  cp -R "$scratch/dd/Build/Products/Debug-iphonesimulator/WorkoutTracker.app" "$tmp/"
  write_stamp "$tmp/WorkoutTracker.app" "$sha" 0 cache
  mv "$tmp" "$root/$sha"
  drop_cache_scratch "$scratch"
  exec 8>&-
}

target_app() {
  load_worktree_build
  if [ -n "$at" ]; then
    ensure_cached "$at"
    app=$(cached_app_path "$at")
  else
    [ -n "$built" ] || { echo "no built app for $project; run: $0 build" >&2; exit 65; }
    app=$built
  fi
  read -r want_hash want_commit want_dirty want_origin <<< "$(identity_of "$app")"
  wanted_line=$(identity_line "$want_hash" "$want_commit" "$want_dirty" "$want_origin")
  launched_line=$wanted_line
  [ -z "$at" ] || launched_line="$wanted_line; $(worktree_build_note)"
}

record_refusal() {
  echo "$1" >&2
  [ -n "${VERIFY_RUN:-}" ] || return 0
  mkdir -p "$state_dir"
  printf '%s\n' "$1" > "$state_dir/refused.$VERIFY_RUN"
  printf '%s %s refused: %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$cmd" "$1" >> "$(run_dir)/launches.txt"
}

refuse() {
  trap - EXIT
  record_refusal "$1"
  exit "$2"
}

report_unchanged() {
  [ $? -ne 0 ] || return 0
  record_refusal "app on $sim unchanged: $(installed_line); this $cmd wanted $wanted_line"
}

claim_for_install() {
  resolve_sim
  [ -z "$at" ] || at=$(resolve_commit "$at")
  sim_available "$sim" || exit
  target_app
  trap report_unchanged EXIT
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
  refuse "$sim holds $(identity_line "$hash" "$commit" "$dirty" "$origin"), and this launch would replace it with $wanted_line. To run the cached build: launch --at ${commit:0:8} $fixture. To replace it: install, then launch." 65
}

install_app() {
  local installed
  xcrun simctl install "$sim" "$app" || refuse "simctl install failed, so $sim holds $(installed_line), not $wanted_line" 70
  installed=$(installed_app)
  [ -n "$installed" ] && [ "$(app_hash "$installed")" = "$want_hash" ] \
    || refuse "after simctl install, $sim holds $(installed_line), not $wanted_line that this $cmd installed from $app" 70
  trap - EXIT
  [ -z "${VERIFY_RUN:-}" ] || rm -f "$state_dir/refused.$VERIFY_RUN"
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
  begin_run >/dev/null
}

record_launch() {
  printf '%s %s %s on %s from %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$fixture${animated:+ animated}" "$launched_line" "$sim" "$repo" \
    >> "$(run_dir)/launches.txt"
}

await_front() {
  for _ in $(seq 1 40); do
    if [ "$(front_pid)" = "$pid" ]; then
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

require_own_app() {
  local owner pid
  [ -n "${VERIFY_RUN:-}" ] || return 0
  if [ -f "$state_dir/refused.$VERIFY_RUN" ]; then
    echo "the last launch of run $VERIFY_RUN on $sim was refused, so this would drive whatever that refusal left running ($(cat "$state_dir/refused.$VERIFY_RUN")); launch again: SIM=$sim VERIFY_RUN=$VERIFY_RUN $0 launch <fixture>" >&2
    exit 75
  fi
  owner=$(cat "$state_dir/run" 2>/dev/null) || return 0
  [ "$owner" != "$VERIFY_RUN" ] || return 0
  pid=$(cat "$state_dir/pid" 2>/dev/null) || return 0
  is_fixture_launch "$pid" || return 0
  echo "the app on $sim belongs to run $owner (pid $pid), not to $VERIFY_RUN, so this would drive another run's app; launch yours first: SIM=$sim VERIFY_RUN=$VERIFY_RUN $0 launch <fixture>" >&2
  exit 75
}

reset_keyboard() {
  if xcrun simctl spawn "$sim" defaults write com.apple.keyboard.preferences AutomaticMinimizationEnabled -bool false; then
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

cmd=${1:-}
[ -n "$cmd" ] || usage
shift
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
    launch_args
    start_app
    record_launch
    await_front
    ;;

  doctor)
    resolve_sim
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
    exit $rc
    ;;

  tree)
    resolve_sim; ensure_axe
    all=${1:-}
    [ -z "$all" ] || [ "$all" = --all ] || usage
    describe | python3 "$tree" flat ${all:+--all}
    ;;

  find)
    resolve_sim; ensure_axe
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
        | python3 "$tree" landing "${resolved#*$'\n'}" "$front"
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

  stop)
    resolve_sim
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

  axe)
    resolve_sim; require_own_app; ensure_axe
    rc=0
    "$axe" "$@" --udid "$sim" || rc=$?
    case ${1:-} in key|key-sequence|key-combo|type) reset_keyboard ;; esac
    exit $rc
    ;;

  *) usage ;;
esac
