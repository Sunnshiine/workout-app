# Tap

Read `SKILL.md` first; its Drive section names the verbs and the order to target elements in. This
file is the reference for what `tap` checks and what it reports.

`tap --id` polls up to 3 s for that element to be enabled, on screen, and with its centre inside the frame of every
element that contains it. A container with a zero width or height holds no point, so it is skipped,
and so is one that covers the whole screen, such as a full-screen scroll area, whose edges the
screen check already covers.
The keyboard toolbar wraps `Done` in a 0x0 group. The tap point is the centre of the part of the
element that the screen and those containers show, rounded to a whole point inside that part, so a
row half below the fold is tapped in its visible half. When no point of it is left, the tap is
refused as `off-screen` or `clipped`. Last, `tap --id` asks axe what is on top at that point. The
answer must belong to the app in front and be the element or something inside its frame, and then
it taps that point. A system prompt over the app is covered. The pid file that
`launch` writes decides when this check runs:

- While the app `launch` started is in front, the check runs.
- While another pid is in front, the check stands aside and the tap goes by the tree alone. `tap`
  prints `not checked for cover:` on stderr with both pids. This covers the Home Screen, another
  app, and the app relaunched under a new pid, which `doctor` flags.
- With no pid file, after `stop` or for an app `launch` did not start, the check runs for whatever
  is in front. On the Home Screen axe's point read can name a neighbouring icon, and then the tap
  is refused as `covered`.

That second read makes a tap that lands take about 3 s, against about 2 s without it.

When `tap --id` never gets a hit that passes every check, it exits 1 and says `off-screen`,
`clipped`, `disabled`, or `covered`. A refusal takes 4 s or more, because it polls the full 3 s and
then reads once more. A `clipped` note names the container whose frame misses the centre, or
misses every point of the element the screen shows, such as the RPE track. A `covered` note names what is on top instead, such as an alert's backdrop, or
whatever took the place of an element that went away after the tree was read. So a tap that reports
success aimed at an element that was on screen, enabled, inside every container that clips it, and
on top, unless it printed `not checked for cover:`. The tap lands up to about a second after that
last look, and an element that leaves in that second still reports success. So prove a tap by
what it changed.

`tap --label` resolves its element through the tree the same way, with the same poll and the same
notes. It matches the whole label as `tree` prints it, case included. When a control and a text
carry the label, it taps the control. When more than one is left, it exits 1 and lists each with
its centre. With the sign-out confirmation up, `tap --label "Sign Out"` lists the Settings row and the
confirmation's own button, so tap that button by its id, `sign-out-confirm-button`. `tap -x -y` resolves no
element, so it still reports success whatever is under the point.
