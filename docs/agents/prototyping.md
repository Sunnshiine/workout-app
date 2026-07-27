# Prototyping

How the `/prototype` skill's UI branch renders in this repo. The skill owns *what* to
build — the variant discipline, the switcher, the throwaway rules
(`.claude/skills/prototype/UI.md`); this doc owns *where it renders*. The review
surface is the user's iPhone either way.

## Pick a render target: look vs. feel

- **HTML render** — a self-contained HTML file with `?variant=` (or `#hash`)
  switching. Minutes per iteration. Trust it for **look**: layout, information
  hierarchy, which affordance is primary.
- **Device build** — SwiftUI variants on a throwaway PR, shipped to the phone as
  **WT Dev** via the `testflight` label. ~40 minutes per build. The only target that
  can settle **feel**: Liquid Glass materials, motion, gestures, scroll physics,
  real data density inside the real app.

The test: **would a screenshot settle it?** Yes → HTML render. Only holding the
phone settles it → device build. When the question has both halves, sketch the
structure in HTML first and spend one device build validating the winner's feel —
exploration is cheap in the browser and expensive on CI.

State the chosen target and why in one line alongside the skill's variant plan,
before building anything.

## HTML render

Standalone HTML files — this repo has no web app to host routes in, so the skill's
"new page" sub-shape is the norm here. Verify at an iPhone viewport before handover:

```bash
npm run prototype:capture -- <file>
```

This screenshots every variant at a current-generation iPhone descriptor. Embed the
PNGs in the issue comment — that's where review actually happens.

## Device build

1. **Branch and variants.** Create a throwaway branch (`prototype/<name>`). Build
   the variants as SwiftUI views following the skill's variant discipline, hosted
   inside the real screen they'd live in (the skill's "existing page" sub-shape) so
   each variant butts up against real navigation, Theme, and data. Switch variants
   with an on-screen floating switcher — arrows plus variant label, the same anatomy
   as the skill's bottom bar. It lives only on this branch, so it needs no
   production gating.
2. **Throwaway PR.** Open a draft PR titled `[PROTOTYPE] <question>`. Body: the
   question, the variant list and how to switch, and "Throwaway — never merges.
   Close when the question is answered." This PR doubles as the skill's capture
   branch: the primary source survives here when it closes unmerged.
3. **Ship it.** Apply the `testflight` label. One label application builds the
   current head once; the workflow removes the label when the run starts, so
   after a push just apply it again for a new build. Label semantics, the
   AGENT_PAT quirk (a label applied with the plain `GITHUB_TOKEN` never fires
   the workflow), and the pipeline live in `docs/ci/testflight.md`.
4. **Hand over.** The workflow posts a receipt comment when the build is
   installable. Point the user at **WT Dev** in TestFlight and restate the variants
   and switcher. Dev builds run against the live Sheets API — remind them to point
   the picker at a **cloned** training log, never the coach-managed Sheet.
5. **Capture and close.** Record the verdict — winning variant and why — as a PR
   comment, fold the winner into real code through the normal implementation path,
   and close the PR unmerged. Done means: verdict recorded, PR closed, nothing from
   the prototype on main.
