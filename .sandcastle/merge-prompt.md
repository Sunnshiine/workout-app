# TASK

Merge the following branches into the current branch:

{{BRANCHES}}

For each branch:

1. Run `git merge <branch> --no-edit`
2. If there are merge conflicts, resolve them intelligently by reading both sides and choosing the correct resolution
3. This sandbox is Linux and cannot run `swift test` — after resolving conflicts, re-read the merged result carefully to confirm both sides' intents survived. CI verifies on macOS after push.
4. If a resolution looks unsafe, prefer the side that matches the issue's stated goal and note the trade-off in the commit body

After all branches are merged, make a single commit summarizing the merge.

# CLOSE ISSUES

For each branch that was merged, close its issue. If there are any parent issues (such as PRD's) which closing the issue would complete, close those too.

Here are all the issues:

{{ISSUES}}

Once you've merged everything you can, output <promise>COMPLETE</promise>.
