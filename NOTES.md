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
  truth. Reuse each artifact's URL on redeploy (one stable URL per document).
  Still to publish: lesson 0001, reference/interface-map.html, reference/glossary.html.
- Lessons and reference docs are HTML linking `assets/course.css`.
- Interface facts in lessons must come from the actual codebase (signatures verified at
  time of writing) — cite `file:line` so drift is detectable.
