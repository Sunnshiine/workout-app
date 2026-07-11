# Deep-Module Interfaces Resources

## Knowledge

- [Repo: `.claude/skills/codebase-design/SKILL.md`](.claude/skills/codebase-design/SKILL.md)
  The house glossary — module, interface, seam, adapter, depth-as-leverage. This is the
  vocabulary every lesson must use. Note it explicitly *rejects* Ousterhout's
  implementation-to-interface line ratio in favour of depth-as-leverage.
- [Repo: `CONTEXT.md`](CONTEXT.md)
  The domain glossary (Block, Session, Set Log, Current Session, Move On, Superset…). The
  domain language *is* part of each interface's contract — parameter and return types are
  named in these terms.
- [Repo: `docs/adr/`](docs/adr/)
  Architectural decisions behind the seams (ADR-0001: Sheet as source of truth with local
  cache). Use for: *why* a seam is where it is.
- [Book: _A Philosophy of Software Design_ — John Ousterhout](https://web.stanford.edu/~ouster/cgi-bin/book.php)
  Origin of "deep modules" (ch. 4), information leakage, and "define errors out of
  existence". Use for: the general theory behind the house style. Read with the house
  correction: depth is leverage, not a line ratio.
- [Talk: "A Philosophy of Software Design" — John Ousterhout, Google Talk (2018)](https://www.youtube.com/watch?v=bmSAYlu0NcY)
  1-hour video version of the book's core argument. Use for: the fastest high-trust
  introduction to deep vs shallow modules.
- [Paper: "On the Criteria To Be Used in Decomposing Systems into Modules" — D. L. Parnas (1972)](https://dl.acm.org/doi/10.1145/361598.361623)
  The primary source for information hiding: modularize around design decisions likely to
  change, not around steps in the flowchart. Use for: judging where a seam belongs.
- [Book chapter: "Seams" — Michael Feathers, _Working Effectively with Legacy Code_ (ch. 4)](https://www.oreilly.com/library/view/working-effectively-with/0131177052/)
  The origin of the **seam** concept the house glossary uses. Use for: what makes a seam
  real vs hypothetical, and testing through interfaces.

## Wisdom (Communities)

- [Software Engineering Stack Exchange](https://softwareengineering.stackexchange.com/)
  Design-question forum with strong moderation. Use for: sanity-checking an interface
  design decision against outside practitioners.
- [r/ExperiencedDevs](https://reddit.com/r/ExperiencedDevs)
  Practitioner discussion with low tolerance for cargo-culting. Use for: "is this module
  too shallow / this seam premature?" debates.

## Gaps

- No high-trust external source specifically on module design for SwiftUI apps backed by a
  remote source-of-truth; the repo's own ADRs are the best material for that.
