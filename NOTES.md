# Teaching Notes

## User preferences
- **Visual learner.** Lead every lesson with a diagram (iceberg views, module maps, arrows
  between interfaces). Prose annotates the picture, not the other way round.
- Explicitly does *not* want to look "under the iceberg" — never quote implementation code
  in lessons; quote only public signatures and contracts.
- Goal is architectural judgement, not trivia: quizzes should pose "where does this feature
  go?" decisions, not "what is the third parameter?" recall.

## House vocabulary
Use the repo's `codebase-design` skill glossary exactly: **module, interface, implementation,
depth, seam, adapter, leverage, locality**. Depth is leverage-at-the-interface, not
Ousterhout's line-count ratio (that framing is explicitly rejected in the skill). Also use
the domain language from `CONTEXT.md` (Block, Session, Set Log, Current Session, Move On…).

## Workspace conventions
- **Publish every lesson and reference doc as a claude.ai Artifact** so the user can view it
  on mobile (attachments don't render HTML inline on the mobile app). Artifacts were
  re-enabled in `.claude/settings.json` on 2026-07-11; sessions started before then lack the
  Artifact tool. When publishing, inline `assets/course.css` / `assets/quiz.js` (and embed
  `module-map.svg`) — artifacts must be self-contained; the repo files stay the source of
  truth. Reuse each artifact's URL on redeploy (one stable URL per document) — pass the URL
  below as the Artifact tool's `url` param since a fresh conversation didn't publish it.
  Note: the `artifact-design` skill is a *bundled* skill and this repo's
  `.claude/settings.json` has `disableBundledSkills: true`, so it won't appear in a fresh
  session's skill list even though the Artifact tool itself is enabled — apply the Artifact
  tool's own self-contained/theme-aware/favicon requirements directly instead.
  Published 2026-07-11:
  - Lesson 0001 — https://claude.ai/code/artifact/7e993ce4-4e8a-464b-851d-ae1630d6da62 (favicon 🧊)
  - reference/interface-map.html — https://claude.ai/code/artifact/a97b065c-accd-4e68-bd83-d4aebb856fdc (favicon 🗺️)
  - reference/glossary.html — https://claude.ai/code/artifact/febbe2d6-511c-4422-96f6-ef7f363a2e09 (favicon 📖)
- Lessons and reference docs are HTML linking `assets/course.css`.
- Interface facts in lessons must come from the actual codebase (signatures verified at
  time of writing) — cite `file:line` so drift is detectable.
