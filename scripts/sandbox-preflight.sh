# shellcheck shell=bash
# Sourced by test-sim.sh and verify.sh before an Xcode build.

# hostgate's probe takes about 7 s to report stuck reporting, so a shorter bound would wave through the
# very builds this check exists to stop.
host_knob WORKOUT_SANDBOX_CHECK_SECONDS 12 1

# A build started while macOS sandbox reporting is stuck hangs at the SwiftLint plug-in until the
# operator clears it, so hostgate checks first, before the caller takes a simulator. A missing or old
# hostgate is reported once, by hostgate_run in sim-lock.sh, and the build goes ahead, as on CI. On a
# fail finding it prints the finding and $1, then exits 75. Any other outcome, a broken install's exit 1
# included, prints one WARNING line and builds.
check_sandbox_report() {
  local out rc=0 said
  command -v hostgate >/dev/null || return 0
  # The output goes to a file, so a child the check leaves behind cannot hold the shell past the bound. The
  # group's 2>/dev/null takes only bash's "Alarm clock" report; the timeout gets its own line below.
  said=$(mktemp "${TMPDIR:-/tmp}/sandbox-check.XXXXXX")
  { perl -e 'alarm shift; exec @ARGV or exit 127' "$WORKOUT_SANDBOX_CHECK_SECONDS" \
    hostgate check --only sandbox-report >"$said" 2>&1; } 2>/dev/null || rc=$?
  out=$(cat "$said")
  rm -f "$said"
  if [ $rc = 1 ] && grep -q '^fail sandbox-report' <<< "$out"; then
    printf '%s\n%s\n' "$out" "$1" >&2
    exit 75
  fi
  case $rc in
    0) ;;
    142) echo "WARNING: hostgate check --only sandbox-report did not finish within $WORKOUT_SANDBOX_CHECK_SECONDS s (WORKOUT_SANDBOX_CHECK_SECONDS), so nothing checked sandbox reporting; building anyway" >&2 ;;
    *) echo "WARNING: hostgate check --only sandbox-report exited $rc, so nothing checked sandbox reporting; building anyway${out:+. It printed: $(tail -n 1 <<< "$out")}" >&2 ;;
  esac
}
