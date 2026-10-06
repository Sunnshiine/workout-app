# The lights-on software factory

An 18-slide talk about redesigning WorkoutTracker with cloud agents. The deck is one HTML file with
no build step and no network access.

## Open it

```bash
open -a "Google Chrome" presentations/cloud-workflow/index.html
```

The stage is 1920x1080 and letterboxes to any window at 16:9.

## Keys

Most slides build up one press at a time. Each press of next reveals the slide's next step, and
moves to the next slide only after the last step.

| Key | Action |
| --- | --- |
| Right, Down, Space, Enter, Page Down | Reveal the next step, or go to the next slide |
| Left, Up, Backspace, Page Up | Hide the last step, or go back to the previous slide fully revealed |
| Home, End | First slide, or last slide fully revealed |
| F | Toggle fullscreen |

A clicker that sends Page Up and Page Down works. To open a given slide, add `#N` to the URL for
the slide at its first state, or `#N.S` for step S. For example, `index.html#7.3` opens slide 7
with three steps revealed. The address bar follows along as you present.

## Present with notes

1. Open `index.html?presenter` in Chrome. This window shows the slide as the room sees it, what
   the next press will show, the speaker notes, a clock, and a counter that reads
   `slide N / total · step s / max`. Click the clock to reset it.
2. Click **Open audience window**.
3. Drag the audience window to the projector and press F in it.
4. Drive either window. The other one follows.

A bold **[click]** in the notes marks where to press next; the notes read in order, one cue per
step. The last paragraph of each note, in brackets, lists its sources for questions. The presenter view
shows it smaller and dimmer so it is not read aloud. If you reload the presenter window, press any
key in the audience window to link the two again.

## Role chips

Every image carries a small chip that says what it is. Drawings without a chip were drawn for
this talk.

| Chip | Meaning |
| --- | --- |
| `APP RENDER · <sha>` | A simulator Visual Baseline of the app at that commit. A fixture name, as in `APP RENDER · Active Set Card fixture · <sha>`, marks a single component rendered from test data. |
| `AUDIT RENDER of PR #467 · <sha>` | The audit branch's render of the first, blind implementation, not a photo of the phone build. |
| `PRODUCTION · redrawn in HTML` | The production screen of the time, redrawn in HTML to sit beside the prototypes. |
| `PROTOTYPE · browser render` | An HTML prototype rendered in a browser, not the app. |
| `PROTOTYPE · accepted pick` | A prototype the owner accepted as the design. |
| `TICKET · #N` | Text quoted from that GitHub issue. |
| `RUN RECORD` | Text or times from GitHub Actions runs and their receipts. |
| `agent's record` | A GitHub comment written by the agent to record the owner's verdict. |

`my words · #505` marks the owner's own typed feedback, quoted verbatim.

## Sources and assets

- `notes/sources.md` traces every fact on a slide or in the notes.
- `notes/assets.md` maps each file in `assets/` to its source path and commit.

## Rebuild and check

The images come from the talk's asset staging folder, outside this repo. Rebuild them with the
staging folder's Python:

```bash
<staging>/_tools/venv/bin/python -I presentations/cloud-workflow/tools/build-assets.py <staging>
```

This rewrites `assets/`, `fonts/`, and `notes/assets.md`.

Three checks need Chrome and a folder with `playwright-core` in its `node_modules`, passed as the
first argument:

```bash
node presentations/cloud-workflow/tools/check-deck.mjs <dir with node_modules> presentations/cloud-workflow/index.html /tmp/deck-renders
node presentations/cloud-workflow/tools/check-content.mjs <dir with node_modules>
node presentations/cloud-workflow/tools/check-sync.mjs <dir with node_modules>
```

`check-deck.mjs` presses next from the first slide to the last step of the last, screenshots every
state as `slide-NN-sMM.png` and each slide's final state as `slide-NN.png`, and fails when a step
reveals nothing, a slide never becomes active, an image breaks or lacks alt text, notes are thin,
content overflows, Back or the `#N.S` deep link lands wrong, or the presenter view loses its
notes, step counter, or step-aware Now and Next frames. It repeats the walk with reduced motion,
into `reduced/`, and renders the presenter at 1440x900 and 1280x720.
`check-content.mjs` checks type sizes, role chips, dashes, speaker-note length, and that each
slide's notes carry one bold `[click]` per step.
`check-sync.mjs` checks that the presenter and audience windows drive each other, step by step.
