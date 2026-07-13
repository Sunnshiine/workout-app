# TASK

Review the code changes on branch {{BRANCH}} for issue #{{ISSUE_NUMBER}}: {{ISSUE_TITLE}}

You are an expert code reviewer focused on enhancing code clarity, consistency, and maintainability while preserving exact functionality.

# CONTEXT

<issue>

!`gh issue view {{ISSUE_NUMBER}}`

</issue>

<diff-to-main>

!`git diff main..HEAD`

</diff-to-main>

# REVIEW PROCESS

## 1. Read the diff and look for anything dodgy

Read the diff carefully. For anything that looks suspicious — fragile logic, unchecked assumptions, tricky conditions, force-unwraps, missing guards — write a test that exercises it. Try to actually break it. If you can break it, fix it.

## 2. Stress-test edge cases

Go beyond the happy path. For every changed code path, think about what inputs or states could cause problems:

- Empty arrays, empty strings, zero, negative numbers
- Missing optional values, nil handling
- Rapid repeated calls, race conditions, state that changes mid-operation
- Off-by-one errors in loops or index/range operations
- Regressions in adjacent functionality

Write tests for anything that isn't already covered.

## 3. Analyze for code quality improvements

Look for opportunities to:

- Reduce unnecessary complexity and nesting (prefer `guard` early-exits)
- Eliminate redundant code and abstractions
- Improve readability through clear variable and function names
- Consolidate related logic
- Remove unnecessary comments that describe obvious code
- Choose clarity over brevity - explicit code is often better than overly compact code

## 4. Maintain balance

Avoid over-simplification that could:

- Reduce code clarity or maintainability
- Create overly clever solutions that are hard to understand
- Combine too many concerns into single functions or types
- Remove helpful abstractions that improve code organization
- Make the code harder to debug or extend

## 5. Apply project standards

Follow the established coding standards in the project at @.sandcastle/CODING_STANDARDS.md.

## 6. Preserve functionality

Never change what the code does - only how it does it. All original features, outputs, and behaviors must remain intact.

# EXECUTION

This sandbox is Linux — it cannot build this Swift package (`swift test` needs macOS). Verify by careful reading; CI runs `swift test` on macOS when the branch is pushed.

1. Attempt to spot the original bug with new test cases — if you find one, fix it
2. Write edge case tests that stress the implementation
3. Make any code quality improvements directly on this branch
4. Commit with a message starting with `SANDCASTLE: Review -` describing the refinements

If the code is already clean, well-tested, and handles edge cases properly, do nothing.

Once complete, output <promise>COMPLETE</promise>.
