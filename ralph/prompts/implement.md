Issue contract is the source of truth.
Make the smallest reviewable change that satisfies every acceptance criterion.
If a diagnosis artifact exists, trust it unless the code contradicts it.
Consult CONTEXT.md for domain terms and any ADR covering the area you touch.
Stay in the current worktree. Do not edit loop tooling.
Run only the cheapest local checks you need during implementation.
Commit when the change is reviewable.
Stop only when the contract is truthfully met; otherwise return BLOCKED with the concrete missing condition.
