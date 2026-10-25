# shellcheck shell=bash
# Sourced by verify.sh.

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
                              motion on (no -UITEST_DISABLE_ANIMATIONS). Resets the keyboard
                              preference issue 700 names when it is on, and says so
                              fixtures: session settings onboarding long-session partial-block
                                        completed-open-exercises developer-tools
  doctor                      read-only: is the installed app this worktree's build or a cached one, is
                              the running instance ours, current, and answering, and is the software
                              keyboard hidden by the preference issue 700 names?
  tree [--all]                what is on screen, one element per line: role  id  label  value  @x,y wxh
                              an element with neither id nor label prints with empty id and label
                              columns when it has a value or a control, text, or image role;
                              --all adds the off-screen ones (scrolled-out rows, picker tails) and
                              the unnamed layout groups
  find <id>                   one element by accessibility identifier, on screen or off; exit 1 if absent;
                              says on stderr when it is off-screen, clipped, or disabled
  tap --id ID | --label TEXT | -x X -y Y
                              --id and --label wait up to 3 s (--wait-timeout N) for that element
                              to be enabled, on screen, with its centre inside every element of
                              nonzero size containing it short of the whole screen, and on top at
                              the tap point, then tap
                              there. The point is the centre of the part of it the screen and those
                              elements show; exit 1 and say which it was not (off-screen, clipped,
                              disabled, covered). --label is the exact label, a control over a text
                              that shares it; when more than one is left, exit 1 listing each
                              with the point a tap takes. -x -y taps the point and reports whatever it hits
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
  record NAME [--tail S] [-- COMMAND...]
                              NAME.mp4, NAME.take and NAME.end.txt into the run: films from the moment
                              the recorder captures, runs COMMAND (a drive command, launch included),
                              then S more seconds (default 2), stamps load, timing, frames and the
                              verdict, and saves the tree at the take's end as `tree` prints it.
                              Waits first while the 1-minute load is over WORKOUT_LOAD_LIMIT. Exit 0 VALID, 3 INVALID
                              (both kept, reasons on stderr), 1 COMMAND failed, 70 recorder or ffprobe
                              failed, or the screen size or the card's frame could not be read from the
                              tree after the take (nothing kept, a VALID take included), 75 nothing ran
                              (simulator held or load never fell). A take whose screen never changed
                              after COMMAND began is INVALID, but any change counts, the rest pill's
                              countdown included, so VALID does not say COMMAND did anything;
                              NAME.end.txt shows what it did
  stop                        terminate the app this run launched; the simulator stays up, and it
                              says when the run has shots that are not on a sheet yet. A run
                              launched with Live Activities on is uninstalled, which ends them
  axe ARG...                  raw axe call with --udid filled in; after a keyboard verb, the same
                              keyboard preference reset as type
Environment: SIM (the UDID of your own simulator, required by every command that touches one; launch
                  boots it and waits for the boot to finish),
             VERIFY_RUN (names the run; give it to launch and every later command remembers it.
                  tap, hold, type, swipe, shot, burst and axe refuse while another run's app is
                  alive on SIM, and after this run's launch was refused until one succeeds. Unset,
                  the run is the one the last launch on SIM started, and unless that run was named
                  a refused launch with VERIFY_RUN unset counts as a refused launch of it. After
                  another launch reclaims your run, a command without it drives that run's app:
                  name your run on every command),
             VERIFY_EVIDENCE (the parent of the run directories; default
                  <main checkout>/.claude/work/evidence/<branch>),
             VERIFY_LIVE_ACTIVITIES=1 (launch without -UITEST_DISABLE_LIVE_ACTIVITIES; for
             features/live-activity.md, and its shots carry the activity overlay),
             VERIFY_RECORD_START (default 10; seconds record gives the recorder to start capturing),
             WORKOUT_LEASE_MINUTES (60; a run's lease on its app. Every command but build, install,
                  diff, sheet and crop renews it, one with no VERIFY_RUN only before it runs out.
                  Once it has, the next launch, install or scripts/test-sim.sh run on SIM reclaims
                  the simulator and stops the app, and every later command for that run but build,
                  install, diff, sheet and crop exits 75 naming who took it, until it launches again),
             WORKOUT_MEM_FLOOR (25), WORKOUT_SIM_CAP (10), WORKOUT_BUILD_SLOTS (2) and
             WORKOUT_ADMIT_WAIT (540): launch and install wait while free memory
                  (kern.memorystatus_level, percent) is under the floor, and before a boot while
                  WORKOUT_SIM_CAP others are booted; build, and a build into the app cache, wait for
                  the floor, for free disk of WORKOUT_DISK_FLOOR (4096 MB), and for one of the
                  host's build slots. A floor of 0 turns it off.
                  At the cap, a boot first shuts down one idle workout-lane-* simulator, as
                  scripts/test-sim.sh --help says, unused for WORKOUT_IDLE_MINUTES (2). Under
                  the cap, a boot shuts down one lane unused for WORKOUT_SLEEP_MINUTES (30).
                  A wait says why once a minute, and exits 75 after WORKOUT_ADMIT_WAIT seconds,
                  restarted each time a build slot changes hands.
             WORKOUT_LOAD_LIMIT (50): record waits while the 1-minute load is over it, and a take
                  whose load ends over it is INVALID, since a loaded host films a move as a cut.
Exit 75: another run holds SIM or owns its app, this run was reclaimed or its last launch was
         refused, or a wait for the host ran out.
Evidence: <VERIFY_EVIDENCE>/<run>/ survives stop and worktree removal; its launches.txt names the
          app each launch ran.
EOF
  exit 2
}
