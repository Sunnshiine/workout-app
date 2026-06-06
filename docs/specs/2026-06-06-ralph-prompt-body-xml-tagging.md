# Ralph Prompt Body XML Tagging Spec

## Goal

Replace the flat markdown `##` section headers inside each Ralph phase prompt
file with XML section tags, following Anthropic's prompting best practices.

The outer `<ralph_phase>` envelope already ships (PR #268). This spec covers the
*inner* content of `<phase_instructions>`: the bodies of `ralph/prompts/*.md`
currently use `## Contract`, `## Work`, and `## Completion gate` markdown headers.
Converting these to XML section tags — `<contract>`, `<work>`, `<completion_gate>`,
`<role>`, and phase-specific additions — makes the prompt body unambiguous for the
model and consistent with the structured envelope that wraps it.

## Background

Anthropic's prompting best practices state that XML tags reduce ambiguity when a
prompt mixes instructions, context, examples, and variable inputs; that tag names
should be descriptive; and that nesting is appropriate when content has a natural
hierarchy. The current prompt bodies sit inside `<phase_instructions>` as plain
markdown. The outer envelope now uses XML throughout; the inner body is the
remaining gap.

Relevant docs:

- [Ralph Programmatic Issue Context Prompts Spec](2026-06-06-ralph-programmatic-issue-context-prompts.md) — the predecessor spec; outer envelope shipped in PR #268
- [Claude prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices)
- [Ralph README](../../ralph/README.md)

## Decisions

- Decision: Sections stay **inside** `<phase_instructions>` — not promoted to first-class envelope siblings.
  - Source: architecture grilling, 2026-06-06.
  - Consequence: No changes to `ralph/orchestrator/loop.py`. The `.md` files are
    still read verbatim and dropped into `<phase_instructions>`.

- Decision: A `<role>` tag wraps the opening "You are…" persona paragraph.
  - Source: architecture grilling, 2026-06-06.
  - Consequence: Every section of the prompt body is tagged; there is no untagged
    prose mixed with tagged sections.

- Decision: Section tags are `<contract>`, `<work>`, `<completion_gate>`, matching the existing section names.
  - Source: architecture grilling, 2026-06-06.
  - Consequence: Tag names are precise and domain-meaningful, not generic names
    like `<instructions>` or `<context>`.

- Decision: Hybrid inner format — XML named elements for genuinely categorised content; markdown bullets for sequential constraint lists.
  - Source: architecture grilling, 2026-06-06.
  - Consequence: The three test-type categories in `ui-verify.md` become named XML
    elements (they are distinct things the model must reason about separately);
    sequential constraint lists remain markdown bullets inside their section tag.

- Decision: `<diagnosis-authority>` template blocks in `diagnose.md` are wrapped in `<example>` tags.
  - Source: architecture grilling, 2026-06-06; Anthropic docs.
  - Consequence: The model can distinguish "examples to copy" from "instructions
    to follow" without relying on a fenced code block convention alone.

- Decision: `select.md` is excluded from this pass.
  - Source: architecture grilling, 2026-06-06.
  - Consequence: `select.md` is not injected via the phase envelope and has a
    different structure. It is out of scope here.

- Decision: `parse_promise` byte-exact lines must not be XML-wrapped or reflowed.
  - Source: `ralph/orchestrator/engines.py` parse_promise contract.
  - Consequence: The COMPLETE and BLOCKED promise lines appear unmodified at
    the end of a model response; the prompt body may reference them but must not
    wrap them in tags.

## Scope

### In

- Rewriting `## Contract`, `## Work`, `## Completion gate` (and phase-specific
  additional sections) in:
  - `ralph/prompts/implement.md`
  - `ralph/prompts/ui-verify.md`
  - `ralph/prompts/review.md`
  - `ralph/prompts/diagnose.md`
  - `ralph/prompts/diagnose-format.md`
- Wrapping the "You are…" persona paragraph in `<role>` in each file.
- Converting the test-type taxonomy in `ui-verify.md` `<work>` to named XML elements.
- Wrapping `<diagnosis-authority>` template examples in `<example>` tags in `diagnose.md`.
- Updating prompt-contract tests in lockstep with every body change.

### Out

- Changes to `ralph/orchestrator/loop.py` or the outer envelope structure.
- Changes to `ralph/prompts/select.md`.
- Changes to context artifacts, authority gates, or promise parsing.
- Converting every bullet point in every file to XML elements.
- Publishing issues or creating a product PRD.

## Current Architecture

`_phase_prompt` in `ralph/orchestrator/loop.py` reads each `.md` file verbatim
and drops it inside `<phase_instructions>`:

```xml
<phase_instructions>
## Contract
- Rule bullets…

## Work
- Work bullets…

## Completion gate
Emit COMPLETE only when…
</phase_instructions>
```

The markdown `##` headers provide human readability but give the model no
structured signal for where one type of content ends and another begins.

## Target Architecture

Same slot, XML-sectioned bodies:

```xml
<phase_instructions>

<role>
You are an autonomous engineer…
</role>

<contract>
- Rule bullets…
</contract>

<work>
- Work bullets…  (or named elements for categorised content)
</work>

<completion_gate>
Emit COMPLETE only when ALL of these hold:
- …
</completion_gate>

</phase_instructions>
```

`loop.py` is unchanged. The `.md` files remain the source; they now contain
XML-tagged prose instead of markdown-headered prose.

### `diagnose.md` — additional sections

`diagnose.md` has two sections between `<work>` and `<completion_gate>` that
other files lack:

```xml
<diagnosis_handoff>
Your full response is saved as the implementation handoff. Include, in order:
…
</diagnosis_handoff>

<diagnosis_authority_instructions>
Decide whether the fix requires UI integration test edits…

<example>
<diagnosis-authority>
ui_integration_test_edits_required: true
…
</diagnosis-authority>
</example>

<example>
<diagnosis-authority>
ui_integration_test_edits_required: false
…
</diagnosis-authority>
</example>

Rules:
- …
</diagnosis_authority_instructions>
```

### `ui-verify.md` — categorised test types

The `<work>` section in `ui-verify.md` describes three distinct test-type
categories the model must reason about separately. These become named XML elements:

```xml
<work>
<test_categories>
  <category name="visual_regression">…</category>
  <category name="ui_integration_smoke">…</category>
  <category name="ui_interaction_suite">…</category>
</test_categories>

Run UI Integration Smoke class-level selectors…
- Do NOT spawn…
</work>
```

Sequential instructions within `<work>` that are not categorically named remain
as markdown bullets.

## Contracts

### `<phase_instructions>` body format [CHANGED]

Each Ralph phase prompt file body adopts XML section tags in place of markdown
`##` headers.

Rules:

- Every prompt file must open with a `<role>` tag containing the "You are…"
  persona paragraph.
- The three standard sections are `<contract>`, `<work>`, `<completion_gate>`.
- `diagnose.md` adds `<diagnosis_handoff>` and `<diagnosis_authority_instructions>`
  between `<work>` and `<completion_gate>`.
- Content inside section tags may mix markdown bullets and XML named elements.
  XML named elements are used only when items are genuinely distinct named
  categories that the model must reason about separately.
- COMPLETE and BLOCKED promise lines appear unmodified outside any XML tags,
  at the end of the model response — the prompt body references them but does not
  wrap them.
- Fenced code blocks that show template text the model must reproduce are wrapped
  in `<example>` tags.

### `select.md` [UNCHANGED]

`select.md` is not part of the phase envelope and retains its existing structure.

### `loop.py` prompt construction [UNCHANGED]

`_phase_prompt` reads prompt files verbatim and injects them into
`<phase_instructions>`. No change.

## Acceptance Criteria

- [ ] `implement.md`, `ui-verify.md`, `review.md`, `diagnose.md`, and
      `diagnose-format.md` contain no markdown `##` section headers.
- [ ] Each file opens with a `<role>` tag.
- [ ] Each file has `<contract>`, `<work>`, `<completion_gate>` XML sections.
- [ ] `diagnose.md` has `<diagnosis_handoff>` and `<diagnosis_authority_instructions>`.
- [ ] The `<diagnosis-authority>` template examples in `diagnose.md` are wrapped
      in `<example>` tags.
- [ ] The test-type taxonomy in `ui-verify.md` uses named `<category>` elements.
- [ ] No COMPLETE or BLOCKED promise lines are XML-wrapped or reflowed.
- [ ] `select.md` and `loop.py` are unchanged.
- [ ] All prompt-contract tests pass after being updated in lockstep with each
      file change.
- [ ] Full Ralph Python test suite passes: `uv run --python 3.11 python -m unittest discover -s ralph/tests -t .`

## Testing Strategy

Each prompt file is changed in its own commit, with tests updated in the same
commit (TDD: failing assertion first, then file rewrite to make it pass).

Assertions check:
- Old `## Section` headers are absent.
- New `<role>`, `<contract>`, `<work>`, `<completion_gate>` tags are present.
- Phase-specific tags (`<diagnosis_handoff>`, `<category name="...">`, `<example>`)
  are present in the files that need them.
- Invariant phrases (e.g. `gh issue view` absent from implement/ui-verify/review,
  `parse_promise`-matched promise lines byte-exact) are unchanged.

No loop-level integration test is needed; prompt-body tests read the `.md` files
directly.

## Open Questions

- None.
