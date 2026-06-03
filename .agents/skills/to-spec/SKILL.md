---
name: to-spec
description: Turn ADRs, technical decisions, architecture discussions, or brownfield refactor context into an engineering-focused spec. Use when work has no product user stories, when converting ADRs into implementation-neutral specs, or when planning internal architecture migrations, API contracts, state ownership, provider boundaries, or platform refactors.
---

# To Spec

Create an engineering spec from existing decisions and codebase context. Prefer this over `to-prd` when the work is technical architecture, brownfield migration, refactoring, platform infrastructure, API contracts, or internal developer experience.

## Process

1. Gather source material
   - Read any ADRs, existing specs, issue text, and relevant conversation context.
   - If paths are provided, read those files first.
   - If no paths are provided, infer the relevant docs from the user request.

2. Explore the codebase
   - Read local `AGENTS.md` files before inspecting implementation files.
   - Identify current integration points, ownership boundaries, data flow, and likely files/modules.
   - Prefer code facts over assumptions. If a claim can be checked in code, check it.

3. Ask only blocking questions
   - Do not interview by default.
   - Ask only when ambiguity would materially change the architecture, scope, or migration order.
   - Otherwise document assumptions explicitly.

4. Draft the spec
   - Use the template below.
   - Focus on contracts, ownership, migration phases, acceptance criteria, and verification.
   - Do not write implementation steps, issue breakdowns, or detailed code changes.
   - Include small code-shaped examples only when they define an interface or contract.

5. Save the spec
   - Default path: `docs/specs/YYYY-MM-DD-<topic>.md`.
   - If the repo uses another docs layout, follow that convention.
   - If the user requested a specific path, use it.

6. Self-review
   - Check for placeholders, contradictions, vague ownership, and missing deletion criteria.
   - Ensure each ADR decision appears in the spec or is explicitly out of scope.
   - Ensure the spec can feed `to-issues` without needing another design pass.

## Output Rules

- Write the spec file; do not only print it in chat.
- Keep the spec implementation-neutral.
- Do not publish issues.
- Do not create a product PRD unless the user explicitly asks for one.

## Good Inputs

- "Turn these ADRs into a spec."
- "Create an engineering spec for removing Action Queue."
- "Convert this architecture discussion into a spec."
- "Write a brownfield migration spec from this plan."

## Spec template 

# <Title> Spec

## Goal

State what this changes and why. Keep this to one or two paragraphs.

## Background

Describe the current architecture, pain points, and relevant constraints. 

<important>
Always link to ADRs or existing docs. The user may refer to an ADR as context when using this skill, use that ADR. If none exist then do not link anything.
</important>

## Decisions

List accepted decisions that shape the spec. Reference ADRs when available.

- Decision:
- Source:
- Consequence:

## Scope

### In

- What this spec covers.

### Out

- What this spec explicitly does not cover.

## Current Architecture

Describe the existing data flow, ownership boundaries, modules, and integration points.

## Target Architecture

Describe the desired ownership model and data flow. Name the important modules, providers, APIs, contracts, and deletion boundaries.

## Contracts

Define stable interfaces and data shapes. Include examples only when they clarify the contract.

Examples:

- API response shape
- command/event shape
- provider/hook API
- route contract
- bootstrap payload
- migration compatibility adapter

<important>
    You MUST tag contracts with [ADDED], [REMOVED], and [CHANGED] based on the change being introduced.
</important>

## Migration Plan

Only write this section of a migration plan is required. The user may mention if migration is required. Ask if it is ambiguous.

Break the migration into phases. Each phase should be independently reviewable and should reduce risk.

### Phase 1: <Name>

- Change:
- Compatibility:
- Acceptance criteria:

### Phase 2: <Name>

- Change:
- Compatibility:
- Acceptance criteria:

## Deletion Criteria

If applicable, list the conditions that allow old code, adapters, flags, or compatibility paths to be removed.

## Acceptance Criteria

- [ ] Observable completion criterion.
- [ ] Observable completion criterion.
- [ ] Observable completion criterion.

## Testing Strategy

Briefly describe the testing strategy. It does not need to be exhaustive.

## Open Questions

- Only unresolved decisions. Do not include questions that the spec already answers.
