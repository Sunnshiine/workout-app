# Motion

Read `SKILL.md` first; its Motion section says when a take is the proof. This file holds what still
moves under `-UITEST_DISABLE_ANIMATIONS`, what a `burst` shows, the recipe for filming a take, and the
contract for reading one.

## Under the flag

`-UITEST_DISABLE_ANIMATIONS` stops UIKit animations and clears the animation on every SwiftUI
transaction in the main window. Bursts and screen recordings under it, each checked against a run
without it that moved, show one cut from the old screen to the new for these: a log with the
weight keyboard closed, a skip's commit, a Superset log, the Move On celebration opening and
closing, and the pairing state inside the queue sheet. The tapped button can show its pressed
colour for up to about 90 ms before that cut. A Superset log's retiring card never draws. After a
log the sync pill lands a frame or two after the card, reads `Syncing`, then `1 unsynced` under
`-UITEST_OFFLINE`, and moves everything below it down about 20 points, the rest pill included. Two of the five log bursts
saved for issues 618 and 696 caught the new card with no sync pill.

Some states still change under the flag (issue 739). The rest pill's countdown and progress line
change on their own while rest runs. Every rest after the first on the Session screen starts with
the rest pill about 3% larger and brighter for about 150 ms; a burst caught that on a log while
rest ran. Each second from `0:05` to `0:00` the countdown digits grow about 3% for about 230 ms. A
skip hold's fill jumps to a full `Skipped` 250 ms into the press, and the skip lands about 900 ms
in, so a shot in between shows a skip that has not happened. The Log capsule jumps to 0.97 scale at
touch-down and sits there until the finger lifts or the skip lands. In the history sheet the Volume chip
still fades for about 250 ms after a tap (issue 739).

`burst` takes its first frame before the drive command runs and the other eleven after it returns,
timed from the return. In the issue 696 runs the first frame came 1.3 to 8.7 s before it, and a
`hold` spends its whole press inside the drive, so a burst never shows the middle of a hold. After
the return, frames land about 200 ms apart, more than 2 s apart on a busy simulator, and the first
lands 140 to 750 ms after it. A burst that shows only a before and an after says nothing about a
state shorter than those gaps, and a 3% change is easy to miss on the tile, so read the full-size
frames in `<name>.burst/`. Any other path is unproved under the flag; prove it with a take, below. A state an action has not
caused within one second will not appear later. `burst` shows frame by frame what an action
changed.

## Takes

```bash
VERIFY_RUN=card-in verify.sh launch --animated session                 # same lock, pid and install path; motion on
verify.sh record log --tail 3 -- tap --id log-active-set-button          # log.mp4, log.take, log.end.txt
verify.sh stop && verify.sh record appear -- launch --animated session   # a first appear: the launch is the drive
uv run .agents/skills/verify/motion/cardframe.py <run dir>/appear.mp4    # the Active Set Card's box and look per frame
uv run .agents/skills/verify/motion/cardstill.py --control <a commit whose card moves>   # 15 min
```

`record` first waits while the 1-minute load is over `WORKOUT_LOAD_LIMIT` (50), because a loaded host
films a move as a cut. A take whose load ends over it is INVALID. It drives once the recorder
is capturing and stops it with SIGINT. Exit 0 is a VALID take. Exit 3 is INVALID, files kept, reasons
on stderr. Exit 70 means the recorder or ffprobe failed, or the screen size or the card's frame could
not be read from the accessibility tree after the take, and nothing is kept, a VALID take included.
Exit 75 means nothing ran.
The recorder writes a frame only when the screen changes, so a still screen is one frame. A take is
also INVALID when the screen never changed after the drive began, or, with no drive, never changed at
all. Any change counts, the rest pill's countdown included, so `VALID` says the recorder was capturing.
It does not say the drive did anything. While the rest pill counts down, a drive that changes nothing
is `VALID`. `record` also saves the tree at the take's end as `NAME.end.txt`; read it to see that the
drive landed. Whether the card moved is `still=`'s answer. `cardframe.py` is the one frame metric, and it
times frames by their own pts, because ffmpeg's clock puts simctl frames about 0.8 s early. It reads
two things: the card's box, from its edges, and its look, the luminance inside the settled box.
A neighbour such as the rest pill joins the box across a gap only while the pair fits the
height of the `card_pt=` frame `record` stamps from the accessibility tree, and an unbroken run counts at
any height, so a card that shrinks during the take reads its whole range. `still=no` means the box or the
look moved, and `box=` and `look=` say which, on a take whose INVALID reasons, if any, only hide motion
(load, a short window), animations on or off. `still=yes` needs `edges=full` and a card where the tree
puts it: nothing moved on a VALID take with animations on, the card's edges were read from the window's
first frame, and the box sits on the `card_pt=` frame: its middle within 8 pt and its height within 24 pt.
A box still moving in its last frame is held to its height and x only, because the tree is read after the
recorder stops and holds where the card was going. `still=unknown` covers the rest: nothing moved but the take is INVALID,
has animations off, or has `edges=partial`; or something moved on a take INVALID for any other reason,
such as a launch with no fade from black. A take whose tree held no `active-set-card`, or whose box is not
where the tree put it, exits 1 with `no card:` and its reason. A label that swaps in one frame reads
`look=cut` and stays still. A take that presses the Log capsule reads `look=changed` from the press's
0.97 scale, so judge the card there by `box=`. A launch take's window opens at the end of iOS's fade-in, the full-screen
frames in the 0.5 s after the screen leaves black; any later frame that changes three quarters of the
screen makes the take INVALID. So first-appear motion that ends inside that fade is invisible to a launch
take. From the fade's end the window must watch 1.5 s or the take is INVALID. `cardstill.py` prints PASS
only when the control commit moved the card on one of its eight takes and the head held it still on all
eight. Each take's `.end.txt` must show where its drive leads (the next Set active, the review open, then
closed, the partner in front, the rest pill gone), or the take is INVALID.

Judge a take by its reads, never by its numbers. The contract is the exit codes, `VALID` or `INVALID`,
`still=`, `box=`, `look=` and `edges=`. `cardframe.py` exits 0 when it measured, 1 with no card, and 3
when the take is INVALID or animations are not on. A first-appear launch take with `--animated` reads
as follows:

- A card that slides in reads `still=no box=changed look=changed edges=partial`.
- A card that fades in place reads `still=no look=changed edges=partial`. Its `box=` can read `changed`
  by under 1 pt, as two of r6's five fade takes did. `look=changed` decides `still=no` either way, so for
  a fade read `look=`, not `box=`. `cardstill.py` judges the box alone, so there a box that changed by
  over 0.5 pt is a FAIL.
- A card already in place when the window opens reads `still=yes box=still edges=full`.

Without `--animated`, the sliding card reads `still=unknown` and `cardframe.py` exits 3, because
animations off hides the slide.

The numbers vary with the host's load and the build, so take them as rough examples, not limits. They
come from one Mac at load 4 to 12, on two builds of the app after the UI refactor stack (717737ad and
8e495e47). With the default 2 s `--tail`, the launch window watched about 2.2 to 2.9 s. A card sliding
in 300 pt from the right read `worst_edge_range` about 13 to 18 and `look_ms` about 1150. A fade read
`look_ms` just under 1000. At load 34 to 38 the same slide read `worst_edge_range` 1.7 on a VALID take,
with the reads above. A take with those reads is read correctly even when its numbers fall outside these.
