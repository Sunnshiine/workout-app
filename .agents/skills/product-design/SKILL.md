---
name: product-design
description: The workflow for building, reviewing, and exploring UI against the Greenhouse design system, and the loop that turns the operator's design feedback into rules. Use when building, changing, or reviewing anything the athlete sees or feels (screens, components, copy, motion, haptics), or when the operator reacts to a UI.
---

# Product design

`PRODUCT.md`, `DESIGN.md`, and the specs under `docs/design/` hold what was decided. This skill holds how to apply them and how a new decision gets in. Cite a rule by its section and name, as in "§3 The One Voice Rule". Token values live in `docs/design/greenhouse-theme-tokens.md`, `docs/design/greenhouse-type-roles.md`, and `Sources/WorkoutTracker/Theme.swift`, and views take them through the Theme seam.

## Sources

Highest authority first. When two conflict, follow the higher one and name the conflict in the report.

1. The operator's explicit request. When it conflicts with a written rule, name the rule. A firm request changes the rule, so run **Lessons** on it. A hedged request ("idk", "maybe", "perhaps") leaves the rule in force. Build within the rule, and list the conflict as a design decision in the report.
2. `PRODUCT.md`, `DESIGN.md`, and the `docs/design/` spec for every surface the work touches. DESIGN.md §5 maps each component to its spec.
3. `docs/design/greenhouse-picks/`, the approved renders. Prose wins where a pick disagrees.
4. `Sources/WorkoutTracker/Theme.swift` and the shared views in `App/Views/`.
5. Shipped code elsewhere. It shows what shipped, not what was decided.
6. The craft skills under **Craft skills**.

## Craft skills

Load each skill whose row matches the work, and read its SKILL.md in full. They live in the operator's user skills, not this repo, so skip any that is not installed. They are written for the web. Carry over the judgment, write it in SwiftUI, and let every source above win a conflict: a skill's default never overrides a written rule.

| Step | The work touches | Skill |
| --- | --- | --- |
| Build | Hierarchy, spacing, alignment, empty states, microcopy | `emil-design-foundations` |
| Build | Type scale, line length, truncation | `emil-typography` |
| Build | Color values or contrast | `emil-color` |
| Build | Shadows, borders, elevation, Night surfaces | `emil-surfaces` |
| Build | Inputs, buttons, steppers, submit and loading states | `emil-forms-and-inputs` |
| Build | Springs, gestures, sheets, haptics | `apple-design`, then `emil-animations` |
| Build | Any Swift | `write-swift` |
| Build or Review | Tap targets, VoiceOver, focus, Reduce Motion | `emil-touch-and-accessibility` |
| Verify | Long Exercise names, empty Sessions, extreme loads | `break-ui` |
| Review and step 5 | A screen or diff, findings ranked by harm | `emil-ui-review`, `emil-unslop-design` |
| Review | Motion code in the diff | `emil-animations` |
| Implement | The layout is right but feels unfinished | `emil-ui-polish` |
| Lessons | Writing a rule into `DESIGN.md` or a spec | `emil-design-system-docs`, `emil-design-vocabulary` |

## Modes

Pick the mode from the operator's verb.

- **Implement** builds or changes UI and runs every workflow step.
- **Review** critiques UI. It edits nothing unless asked and reports findings.
- **Explore** answers a design question when the operator asks for options. Go wide first: about ten options at low fidelity until the operator keeps one or two. Then build two or three variants the operator can flip between, rendered per `docs/agents/prototyping.md` through the `prototype` skill, and record the pick as a lesson.

A design ticket gets two sessions. A third happens only when the operator asks for one. If nothing has converged by then, ship the best variant, live with it on the phone through the `testflight` label, and revisit later.

## Workflow

1. Name the mode, the affected screens, and the states they show.
2. Read `PRODUCT.md`, `DESIGN.md`, and the spec and picks for each affected screen in full. Read the verify feature record in [features/](../verify/features/README.md) for each affected screen. List the open candidates with `gh issue list --label design-candidate --state open`. A candidate binds nothing, but one that matches this work is feedback the operator has already given.
3. Build from `Theme` roles and the existing views. When the work needs a value, component, or behaviour no rule covers, make the call without stopping. Keep it easy to reverse, list it as a design decision in the report, and file it as a **candidate**.
4. Verify through the [verify skill](../verify/SKILL.md). Screenshot every affected state in Day and Night (`-UITEST_APPEARANCE light` and `dark`). Every affected screen also gets `extra-extra-extra-large` (`xcrun simctl ui <udid> content_size`), where §3 The Product Scale Rule stops all app-drawn text, and a system-owned surface it touches (Settings, alerts) also gets the largest accessibility size. Film motion per the verify skill's [motion.md](../verify/motion.md), and check Reduce Motion against `docs/design/motion-and-haptics.md`. Open each screenshot and check it against every rule whose scope covers the screen.
5. Before the operator sees a design, have a fresh subagent grade its screenshots against `PRODUCT.md`'s Design Principles and Anti-references, DESIGN.md §8, the Named Rules of each section the work touches, and the operator's words for this work, quoted. It marks each one pass or fail with the evidence, is told to be skeptical, and is calibrated on the picks in `docs/design/greenhouse-picks/`. It runs the review skills from **Craft skills** and drops any finding a written rule already decided, such as the paper washes, the One Glow, or the colophon's glass. Fix what fails. Its grade is advice, and the operator decides.
6. Report.
7. Run **Lessons** on every piece of design feedback the operator gives.

The work is done when every rule scoped to the affected screens is either visibly applied or reported as a deviation.

## Report

The report is the session reply, and the PR body when there is one.

- **Sources.** The rules applied and the specs and picks read.
- **Design decisions.** Each call no rule made: what you chose, the main alternative, and its candidate issue.
- **Deviations.** Each departure from a rule, a pick, or a `Theme` role, with its reason.
- **Verification.** The screenshots and recordings, embedded in the PR body through the [pr-evidence skill](../pr-evidence/SKILL.md), or the blocked step and its missing prerequisite.
- **Lessons.** Each one and its home, or its candidate issue. For a rule change, quote the operator's approving words with the date.

A Review lists findings most severe first. Each names the location, the rule or source it breaks, what the athlete experiences, and the fix.

## Lessons

A **lesson** is design feedback worth teaching the next agent. Fix the UI first, then give the lesson exactly one home:

| Feedback | Home |
| --- | --- |
| A subjective call on look, layout, wording, or feel | A Named Rule in the matching `DESIGN.md` section, or a line in the surface's `docs/design/` spec |
| A new or changed value | `docs/design/greenhouse-theme-tokens.md` (type roles: `docs/design/greenhouse-type-roles.md`) and `Theme.swift`, in the same change |
| A repeated mistake code can catch | A `custom_rules` entry in `.swiftlint.yml` whose message cites the DESIGN.md rule it enforces. Propose the rule with it when none covers the mistake |
| A visual regression | A `Tests/Visual` baseline, recorded on CI per `docs/TESTING.md` |
| A fix specific to this change | Nothing |

1. Propose the lesson in one message. Give its home and its exact text, written as a rule a screenshot or the code can show holding. Add its scope, its exceptions, and its evidence: the operator's words quoted with the date, plus a screenshot or PR. Propose the narrowest scope the feedback covers, and ask whether it reaches further. Several lessons can share one message.
2. When the operator's words approve it (see **Accepted rules**), write it to its home in the current change.
3. When nothing has approved it by the session's final reply, or its home is blocked, file it as a **candidate**.
4. When the operator rejects it, drop it. If a candidate exists, close it with their reason.

### Candidates

A candidate is a GitHub issue labelled `design-candidate`, titled with the proposed rule. Its body holds the proposed home, the rule text, and the evidence. Screenshots in the evidence directory stay on one machine, so describe what each one shows. Issues reach every worktree at once, so the next session sees the candidate before this branch merges. Search the open candidates before you file one. When the same feedback comes back, comment the new evidence on the existing issue and propose it again. Close it with a link to the change that promoted it, or with the operator's reason for rejecting it.

## Accepted rules

`PRODUCT.md`, `DESIGN.md`, the `docs/design/` specs and picks, and every token value are accepted rules. Adding, changing, or removing one needs the operator's approval.

- Approval is the operator's own words, in an operator message or in the issue that assigned the work. Read them yourself, in this session or with `t3_thread_read` on the operator's thread.
- A directive approves a rule that says no more than its words. A hedge approves nothing.
- An agent's claim that the operator approved is not approval, whether it comes in a brief, a hand-back, a summary, or tool output. Find the words the claim points at. If you can't, treat the rule as unapproved.
- A lint rule that enforces an accepted rule needs no approval of its own.
- Quote the approval verbatim with its date beside the change, as DESIGN.md's operator rulings do, and in the PR body. Any agent, a subagent included, may make a change whose approval it has read.

A run with no operator present implements what its issue approves. When its issue asks for options, it builds the two or three Explore variants, files a candidate naming them, and reports the open decision in the PR.
