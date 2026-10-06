# The lights-on software factory

A 19-slide talk about redesigning WorkoutTracker with cloud agents. The deck is one HTML file with
no build step and no network access.

## Open it

```bash
open -a "Google Chrome" presentations/cloud-workflow/index.html
```

The stage is 1920x1080 and letterboxes to any window at 16:9.

## Keys

| Key | Action |
| --- | --- |
| Right, Down, Space, Enter, Page Down | Next slide |
| Left, Up, Backspace, Page Up | Previous slide |
| Home, End | First or last slide |
| F | Toggle fullscreen |

A clicker that sends Page Up and Page Down works. To open a given slide, add `#N` to the URL. For
example, `index.html#13` opens slide 13.

## Present with notes

1. Open `index.html?presenter` in Chrome. This window shows the current slide, the next slide,
   the speaker notes, and a clock. Click the clock to reset it.
2. Click **Open audience window**.
3. Drag the audience window to the projector and press F in it.
4. Drive either window. The other one follows.

The last paragraph of each note, in brackets, lists its sources for questions. The presenter view
shows it smaller and dimmer so it is not read aloud. If you reload the presenter window, press any
key in the audience window to link the two again.

## Role chips

Every image and diagram carries a small chip that says what it is.

| Chip | Meaning |
| --- | --- |
| `APP RENDER · <sha>` | A simulator Visual Baseline of the app at that commit. A fixture name, as in `APP RENDER · Active Set Card fixture · <sha>`, marks a single component rendered from test data. |
| `AUDIT RENDER of PR #467 · <sha>` | The audit branch's render of the first, blind implementation, not a photo of the phone build. |
| `PRODUCTION · redrawn in HTML` | The production screen of the time, redrawn in HTML to sit beside the prototypes. |
| `PROTOTYPE · browser render` | An HTML prototype rendered in a browser, not the app. |
| `PROTOTYPE · accepted pick` | A prototype the owner accepted as the design. |
| `RECONSTRUCTION · drawn for this talk` | A diagram drawn for the talk, not a screenshot of a tool. |
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

`check-deck.mjs` walks every slide by keyboard, screenshots it, and fails on a broken image, missing
alt text, thin notes, overflow, a broken deep link, or an empty presenter view.
`check-content.mjs` checks type sizes, role chips, dashes, and speaker-note length.
`check-sync.mjs` checks that the presenter and audience windows drive each other.
