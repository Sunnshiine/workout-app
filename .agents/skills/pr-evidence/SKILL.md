---
name: pr-evidence
description: Put screenshots and videos of the app into a pull request body so they render on GitHub. Use when a PR changes what a user sees or how it moves, or when asked to attach screenshots, a video, or a GIF to a PR.
---

# PR evidence

The helper is `.agents/skills/pr-evidence/evidence.sh` (call it `evidence.sh` here). Run it from
the worktree of the PR's branch. `evidence.sh` with no arguments prints every verb and flag.

## Steps

1. **Capture** on your own simulator with the verify skill. Read `.agents/skills/verify/SKILL.md`
   (Launch, then Evidence) and `.agents/skills/verify/features/README.md` before driving. A still is
   `verify.sh shot NAME`. A video is a take: `verify.sh launch --animated <fixture>`, then
   `verify.sh record NAME -- <drive command>`, as in [motion.md](../verify/motion.md) Takes.
   Exit 3 (INVALID) still keeps the mp4, so read its reasons before you use it. Both land in the
   run's directory, which `launch` prints. Done when `verify.sh sheet` shows the state the PR
   claims and `NAME.end.txt` shows the drive landed.
2. **Convert** each take: `evidence.sh gif <run dir>/NAME.mp4` writes `NAME.gif` beside it. It
   cuts the still lead-in, because the recorder holds one frame until the screen first changes.
   `--from S --to S` picks another span. For a still from a take, list its frame times, then
   take the frame at S seconds:

   ```bash
   ffprobe -v error -select_streams v -show_entries frame=pts_time -of csv=p=0 NAME.mp4
   ffmpeg -ss S -i NAME.mp4 -frames:v 1 NAME-S.png
   ```

   Read the GIF's first and last frames, or the stills, before you publish them.
3. **Publish**: `evidence.sh publish FILE...` with every PNG, GIF, and mp4 the body needs. It
   commits them to the branch `evidence/<your branch>` on origin, never to your PR branch, and
   prints one Markdown line per file. A later publish adds to that branch and leaves earlier links
   working. Keep every `evidence/*` branch after merge, because merged PR bodies still load from it.
4. **Embed** the printed lines in the body's `## Evidence` section. Put a caption
   line above each group that says what it proves. Lines in one paragraph render side by side, so
   a before and after sit on one line. Put each GIF beside its mp4 link. Write the body with
   `gh pr edit <N> --body-file <file>`.
5. **Check**: `evidence.sh check <N>` fetches the PR's rendered HTML and every image in it. Done
   when it exits 0 with an `ok` line for each image you embedded.

## What GitHub renders

Measured on this repository's PR bodies on 2026-10-24:

- A PNG or GIF at `github.com/<repo>/blob/<commit>/<file>?raw=true` renders inline. A GIF
  animates. Without `?raw=true` the URL serves an HTML page and the image shows broken.
- GitHub strips a `<video>` tag. An mp4 link from a branch serves
  `application/octet-stream`, so a click downloads it. Publish a GIF for motion that plays in the
  page, and link the mp4 for full quality.
- Only a `user-attachments` upload plays inline as a video. It needs a signed-in browser
  session: the upload endpoint answers 422 to the `gh` token. When the operator wants an inline
  player, say so in your report. They can drag the mp4 into the PR's edit box.
