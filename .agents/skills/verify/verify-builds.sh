# shellcheck shell=bash
# Sourced by verify.sh: app identity, stamps, worktree builds, and the shared app cache.

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

logged_to() { local log=$1; shift; "$@" > "$log" 2>&1; }

xcodebuild_build() {
  local derived=()
  [ -z "$2" ] || derived=(-derivedDataPath "$2")
  mkdir -p "$(dirname "$3")"
  with_build_slot logged_to "$3" xcodebuild build -project "$1" -scheme WorkoutTracker -destination "platform=iOS Simulator,id=$sim" \
    ${derived[@]+"${derived[@]}"} -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO \
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
    git -C "$repo" -c core.fsmonitor=false worktree add --force --force --quiet --detach "$1/src" "$2" >&2
  fi
  "$repo/scripts/bootstrap-xcode-worktree.sh" "$1/src"
}

# Only xcodebuild keeps fd 4, so a killed install's build holds the cache lock until it exits. A process git
# leaves behind, such as a core.fsmonitor daemon, would hold it for good. The subshell matters: bash 3.2 lets
# children inherit the copy of fd 4 it saves around a function's own 4>&-.
without_cache_lock() { (exec 4>&- && "$@"); }

cached_app_path() { printf '%s/%s/WorkoutTracker.app\n' "$(cache_root)" "$1"; }

ensure_cached() {
  local sha=$1 root app lock scratch tmp
  root=$(cache_root)
  app=$(cached_app_path "$sha")
  cache_hit "$app" && return 0
  mkdir -p "$root/logs"
  lock=$root/$sha.lock
  exec 4>>"$lock"
  python3 -c 'import fcntl, sys
try: fcntl.flock(4, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    print(sys.argv[1], file=sys.stderr, flush=True)
    fcntl.flock(4, fcntl.LOCK_EX)' "waiting for another build of ${sha:0:8} into the app cache (lsof $lock lists it)"
  if cache_hit "$app"; then exec 4>&-; return 0; fi
  scratch=$root/$sha.build
  tmp=$root/$sha.tmp
  without_cache_lock sweep_cache_scratch "$root" "$sha"
  rm -rf "$tmp" "${root:?}/$sha"
  echo "building ${sha:0:8} into the app cache at $root (under a minute to a few; give the call a 10 min timeout)" >&2
  without_cache_lock scratch_checkout "$scratch" "$sha"
  if ! xcodebuild_build "$scratch/src/WorkoutTracker.xcodeproj" "$scratch/dd" "$root/logs/$sha.log"; then
    without_cache_lock drop_cache_scratch "$scratch"
    refuse "app on $sim unchanged: $(installed_line); this $cmd wanted ${sha:0:8} from the app cache, and its build failed" 65
  fi
  mkdir -p "$tmp"
  cp -R "$scratch/dd/Build/Products/Debug-iphonesimulator/WorkoutTracker.app" "$tmp/"
  write_stamp "$tmp/WorkoutTracker.app" "$sha" 0 cache
  mv "$tmp" "$root/$sha"
  without_cache_lock drop_cache_scratch "$scratch"
  exec 4>&-
}

target_app() {
  load_worktree_build
  if [ -n "$at" ]; then
    ensure_cached "$at"
    app=$(cached_app_path "$at")
  else
    [ -n "$built" ] || refuse "app on $sim unchanged: $(installed_line); this $cmd found no built app for $project (run: $0 build)" 65
    app=$built
  fi
  read -r want_hash want_commit want_dirty want_origin <<< "$(identity_of "$app")"
  wanted_line=$(identity_line "$want_hash" "$want_commit" "$want_dirty" "$want_origin")
  launched_line=$wanted_line
  [ -z "$at" ] || launched_line="$wanted_line; $(worktree_build_note)"
}
