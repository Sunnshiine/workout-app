# Issue tracker: GitHub

Issues and PRDs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --json title,body,labels,comments --jq '{title, body, labels: [.labels[].name], comments: [.comments[].body]}'`. Piped, `--comments` prints only the comments, so an issue with none prints nothing.
- **Cite code** in an issue by type or function name, with the path as a hint. Paths and line numbers move; `git grep <Symbol>` finds the code wherever it went.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

The repo is `Sunnshiine/workout-app`. Inside a clone `gh` infers it from `git remote -v`. Outside one,
such as from `/tmp` or another project, `gh` cannot, so run `export GH_REPO=Sunnshiine/workout-app` first.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Read the issue as in **Read an issue** above.
