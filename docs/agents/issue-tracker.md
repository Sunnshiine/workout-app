# Issue tracker: GitHub

Issues and PRDs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

Infer the repo from `git remote -v`; `gh` does this automatically when run inside a clone.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## Issue body conventions for Ralph

Ralph reads issue bodies before autonomous implementation begins. If a
`ready-for-agent` issue intentionally requires changes to UI integration tests
under `Tests/UI/**`, the issue body must include this exact line:

```markdown
UI integration test edits: authorized
```

Put it in a dedicated section such as:

```markdown
## Test authority

UI integration test edits: authorized

Scope: Tests/UI/WorkoutTrackerUITests.swift may be updated to cover the new flow.
```

Only include this marker when UI integration test edits are an intentional part
of the issue contract. Do not rely on comments or Agent Briefs for this
authorization; the body is the durable source Ralph can snapshot before agents
run.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.
