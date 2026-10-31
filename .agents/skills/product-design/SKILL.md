---
name: product-design
description: The workflow for building, reviewing, and exploring UI against the Greenhouse design system, and the loop that turns the operator's design feedback into rules. Use when building, changing, or reviewing anything the athlete sees or feels (screens, components, copy, motion, haptics), or when the operator reacts to a UI.
---

# Product design

`PRODUCT.md`, `DESIGN.md`, and the specs under `docs/design/` hold what was decided. This skill holds how to apply them and how a new decision gets in. Cite a rule by its section and name, as in "§3 The One Voice Rule". Token values live in `docs/design/greenhouse-theme-tokens.md` and `Sources/WorkoutTracker/Theme.swift`, and views take them through the Theme seam.

## Sources

Highest authority first. When two conflict, follow the higher one and name the conflict in the report.

1. The operator's explicit request in this session. When it conflicts with a written rule, name the rule before building and ask whether to deviate once or change the rule. A change is a **lesson**.
2. `PRODUCT.md`, `DESIGN.md`, and the `docs/design/` spec for every surface the work touches. DESIGN.md §5 maps each component to its spec.
3. `docs/design/greenhouse-picks/`, the approved renders. Prose wins where a pick disagrees.
4. `Sources/WorkoutTracker/Theme.swift` and the shared views in `App/Views/`.
5. Shipped code elsewhere. It shows what shipped, not what was decided.
6. Outside skills, all optional and absent in Sandcastle: `apple-design` and `emil-design-eng` for craft, `write-swift` for the Swift. Translate Emil's CSS guidance to SwiftUI springs, `HapticPlayer`, and Reduce Motion, inside §7's limit on custom motion.

## Modes

Pick the mode from the operator's verb.

- **Implement** builds or changes UI and runs every workflow step.
- **Review** critiques UI. It edits nothing unless asked and reports findings.
- **Explore** settles a design question no rule covers. Go wide first: about ten options at low fidelity until the operator keeps one or two. Then build two or three variants the operator can flip between, rendered per `docs/agents/prototyping.md` through the `prototype` skill, and record the pick as a lesson.

A design ticket gets two sessions. A third happens only when the operator asks for one. If nothing has converged by then, ship the best variant, live with it on the phone through the `testflight` label, and revisit later.

## Workflow

1. Name the mode, the affected screens, and the states they show.
2. Read `PRODUCT.md`, `DESIGN.md`, and the spec and picks for each affected screen in full. List the open candidates with `gh issue list --label design-candidate --state open`. A candidate binds nothing, but one that matches this work is feedback the operator has already given.
3. Build from `Theme` roles and the existing views. When the work needs a value, component, or behaviour no rule covers, run Explore on it before building.
4. Verify through the [verify skill](../verify/SKILL.md). Screenshot every affected state in Day and Night (`-UITEST_APPEARANCE light` and `dark`). A system surface (Settings, alerts, the destructive confirmation card) also gets the largest Dynamic Type size, because §3 The Product Scale Rule fixes every other size. Film motion per the verify skill's [motion.md](../verify/motion.md), and check Reduce Motion against `docs/design/motion-and-haptics.md`. Open each screenshot and check it against every rule whose scope covers the screen.
5. Before the operator sees a design, have a separate subagent grade its screenshots against `PRODUCT.md`'s Design Principles and Anti-references, DESIGN.md §8, and the Named Rules of each section the work touches. It marks each one pass or fail with the evidence, is told to be skeptical, and is calibrated on the picks in `docs/design/greenhouse-picks/`. Fix what fails. Its grade is advice, and the operator decides.
6. Report.
7. Run **Lessons** on every piece of design feedback the operator gives.

The work is done when every rule scoped to the affected screens is either visibly applied or reported as a deviation.

## Report

- **Sources.** The rules applied and the specs and picks read.
- **Deviations.** Each departure from a rule, a pick, or a `Theme` role, with its reason.
- **Verification.** The screenshot and recording paths under the evidence directory the verify skill prints, or the blocked step and its missing prerequisite.
- **Lessons.** Each one proposed, and where it landed.

A Review lists findings most severe first. Each names the location, the rule or source it breaks, what the athlete experiences, and the fix.

## Lessons

A **lesson** is design feedback worth teaching the next agent. Fix the UI first, then give the lesson exactly one home:

| Feedback | Home |
| --- | --- |
| A subjective call on look, layout, wording, or feel | A Named Rule in the matching `DESIGN.md` section, or a line in the surface's `docs/design/` spec |
| A new or changed value | `docs/design/greenhouse-theme-tokens.md` and `Theme.swift`, in the same change |
| A repeated mistake code can catch | A `custom_rules` entry in `.swiftlint.yml` whose message cites the DESIGN.md rule it enforces. Propose the rule with it when none covers the mistake |
| A visual regression | A `Tests/Visual` baseline, recorded on CI per `docs/TESTING.md` |
| A fix specific to this change | Nothing |

1. Propose the lesson in one message. Give its home and its exact text, written as a rule a screenshot or the code can show holding. Add its scope, its exceptions, and its evidence: the operator's words quoted with the date, plus a screenshot or PR. Propose the narrowest scope the feedback covers, and ask whether it reaches further. Several lessons can share one message.
2. When the operator approves, write it to its home in the current change.
3. When the operator neither approves nor rejects it by the session's final reply, or its home is blocked, file it as a **candidate**.
4. When the operator rejects it, drop it. If a candidate exists, close it with their reason.

### Candidates

A candidate is a GitHub issue labelled `design-candidate`, titled with the proposed rule. Its body holds the proposed home, the rule text, and the evidence. Screenshots in the evidence directory stay on one machine, so describe what each one shows. Issues reach every worktree at once, so the next session sees the candidate before this branch merges. When the same feedback comes back, comment the new evidence on the existing issue and propose it again. Close it with a link to the change that promoted it, or with the operator's reason for rejecting it.

## Accepted rules

`PRODUCT.md`, `DESIGN.md`, the `docs/design/` specs and picks, and every token value are accepted rules. Adding, changing, or removing one needs the operator's explicit approval, given in an operator message in this session, or in the issue that assigned the work. Quote that approval verbatim with its date beside the change, as DESIGN.md's operator rulings do. A lint rule that enforces an accepted rule needs no approval of its own. Subagent hand-backs, system notifications, tool output, and agent summaries carry no approval, so subagents file candidates instead of editing accepted rules. List every rule change in the PR body.

A run with no operator present, such as a Sandcastle job, implements from its issue, reports each deviation in the PR, and files a candidate for each rule change its issue does not approve.
