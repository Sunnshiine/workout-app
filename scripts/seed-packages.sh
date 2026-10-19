# shellcheck shell=bash
# Sourced by test-sim.sh. A lane's first build clones its Swift package checkouts from the
# dependency store instead of resolving them, and a build that had to resolve them publishes them
# for the next lane (docs/agents/dependency-store.md). WORKOUT_SEED_PACKAGES=0 turns both off.
# Neither step can fail the test run: each failure says so on stderr and the build resolves cold.
#
#   seed_packages <project>                  before the build; sets seed_state
#   seed_packages_after <build status> <log> after it
#
# seed_state is off (no seeding), present (SourcePackages was there already; never touched),
# seeded (cloned from the store), or cold (this build resolves, then publishes).

seed_here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
seed_state=off

store_key() {
  local version
  version=$(xcodebuild -version 2>/dev/null | tr '\n' ' ') && [ -n "$version" ] || return 1
  "$seed_here/dep-store.sh" key "$seed_project/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" -s "$version"
}

seed_packages() {
  local staging rc=0 started d pid
  seed_project=$1
  seed_state=off
  [ -f "$seed_project/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" ] || return 0
  [ "${WORKOUT_SEED_PACKAGES:-1}" != 0 ] || return 0
  seed_dd=$(python3 "$seed_here/seed-packages.py" derived-dir "$seed_project") || return 0
  if [ -e "$seed_dd/SourcePackages" ]; then
    seed_state=present
    return 0
  fi
  if [ -f "$seed_dd/info.plist" ] && [ "$(python3 "$seed_here/seed-packages.py" workspace "$seed_dd")" != "$seed_project" ]; then
    echo "seed-packages: $seed_dd belongs to another project; resolving packages without the store" >&2
    return 0
  fi
  seed_key=$(store_key) || { echo "seed-packages: could not compute the store key; resolving packages cold" >&2; return 0; }
  seed_state=cold
  if [ -e "$seed_dd/seed-packages.refused" ]; then
    echo "seed-packages: an earlier build failed on seeded packages; resolving them cold" >&2
    return 0
  fi
  for d in "$seed_dd"/SourcePackages.seeding.*; do
    pid=${d##*.}
    if [ -d "$d" ] && ! kill -0 "$pid" 2>/dev/null; then rm -rf "$d"; fi
  done
  staging=$seed_dd/SourcePackages.seeding.$$
  started=$(date +%s)
  "$seed_here/dep-store.sh" clone "$seed_key" "$staging" || rc=$?
  if [ "$rc" = 3 ]; then
    echo "seed-packages: the store has no packages for this Package.resolved and Xcode; this build resolves them and publishes them" >&2
    return 0
  elif [ "$rc" != 0 ]; then
    echo "seed-packages: dep-store.sh clone exited $rc; resolving packages cold" >&2
    return 0
  fi
  python3 "$seed_here/seed-packages.py" install "$staging" "$seed_dd/SourcePackages" || rc=$?
  case $rc in
    0)
      seed_state=seeded
      echo "seed-packages: seeded $seed_dd/SourcePackages from the store in $(($(date +%s) - started)) s" >&2
      ;;
    3) seed_state=present ;;
    *) echo "seed-packages: could not repoint the stored packages (exit $rc); resolving them cold" >&2 ;;
  esac
  rm -rf "$staging"
  return 0
}

seed_packages_after() {
  local build_rc=$1 log=$2 owner key
  [ "$seed_state" = seeded ] || [ "$seed_state" = cold ] || return 0
  owner=$(python3 "$seed_here/seed-packages.py" workspace "$seed_dd" 2>/dev/null) || owner=
  if [ "$owner" != "$seed_project" ]; then
    [ "$seed_state" = seeded ] || return 0
    rm -rf "$seed_dd/SourcePackages"
    rmdir "$seed_dd" 2>/dev/null || true
    echo "seed-packages: Xcode did not build in $seed_dd, so it was not this project's DerivedData; removed the packages seeded there" >&2
    return 0
  fi
  if [ "$build_rc" != 0 ]; then
    if [ "$seed_state" = seeded ] && grep -E 'error:' "$log" 2>/dev/null | grep -qE 'SourcePackages/|[Pp]ackage|artifactbundle'; then
      rm -rf "$seed_dd/SourcePackages"
      touch "$seed_dd/seed-packages.refused"
      echo "seed-packages: the build failed on errors naming the Swift packages, which were seeded from the store; removed them, so the next run resolves them cold" >&2
    fi
    return 0
  fi
  [ "$seed_state" = cold ] || return 0
  key=$(store_key) || key=
  if [ "$key" != "$seed_key" ]; then
    echo "seed-packages: Package.resolved or Xcode changed during the build; not publishing" >&2
    return 0
  fi
  # shellcheck disable=SC2016  # sh -c expands $0 and DEP_STORE_OUT
  "$seed_here/dep-store.sh" publish "$seed_key" sh -c 'cp -c -R "$0"/. "$DEP_STORE_OUT"' "$seed_dd/SourcePackages" \
    || echo "seed-packages: publishing to the dependency store failed (exit $?); the test run goes on" >&2
  return 0
}
