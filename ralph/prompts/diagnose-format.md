You are completing a single CORRECTIVE step for a bug diagnosis. Your previous
diagnosis findings were complete, but the `<diagnosis-authority>` block was
missing, malformed, or incomplete. This is the one allowed corrective pass.

The issue number, isolated worktree, branch, and exact promise lines are in the
preamble above. DIAGNOSIS_PATH points at your existing findings.

## Work
- Read DIAGNOSIS_PATH for the findings you already produced. Do NOT re-diagnose,
  re-investigate, edit code, or commit.
- From those existing findings, decide whether the fix requires UI integration
  test edits under `Tests/UI/**`, then emit exactly one corrected block.

When UI integration test edits ARE required:

```text
<diagnosis-authority>
ui_integration_test_edits_required: true
scope: Tests/UI/WorkoutTrackerUITests.swift
reason: Why lower-level coverage cannot prove the fix, per docs/TESTING.md.
</diagnosis-authority>
```

When they are NOT required:

```text
<diagnosis-authority>
ui_integration_test_edits_required: false
scope:
reason:
</diagnosis-authority>
```

Rules:
- `ui_integration_test_edits_required` is `true` or `false` only.
- When `true`, `scope` is required and must name ONLY paths under `Tests/UI/**`,
  and `reason` is required.
- Scope beyond `Tests/UI/**` cannot be authorized here; if the fix needs broader
  test-target wiring, say so in prose and Ralph will escalate for a human.

## Completion gate
Emit COMPLETE only when your response contains exactly one well-formed
diagnosis-authority block and no new code changes or commits.

If you cannot produce a valid block from the existing findings, end with the
exact BLOCKED promise format from the preamble, using this phase's name.

Otherwise end your response with the exact COMPLETE promise line from the
preamble, on its own line.
