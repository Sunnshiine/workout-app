Standards the review agent enforces on top of the repo's own docs. `CONTEXT.md` (domain glossary), `docs/adr/` (binding decisions), `PRODUCT.md` and `DESIGN.md` (product/UI work) always win over anything here. Generic Swift conventions (style, testing mechanics, patterns, security) live in `AGENTS.md` and are not repeated here.

A rule earns a line in this file only when it is not derivable from those docs or the lint/format configs, and it has cost a real bug or a repeated review comment. Delete rules that stop paying rent.

---

Use the domain glossary from `CONTEXT.md` in all names: Block, Week, Session, Exercise, Set, Move On, Open Exercises, Supersets, Load Suggestion. Code that invents synonyms for existing domain terms is wrong even if it works.

---

The Google Sheet is the single source of truth (ADR-0001). The app is a read-write client with a local cache. Any change that lets local state silently diverge from (or overwrite) sheet-derived truth without going through the Stores/sync layer is a correctness bug, not a style issue.

---

Views (`WorkoutTracker/Views/`) are excluded from the SPM library target. Logic that needs unit coverage must live in the library (Models, Parsing, Stores, Progress, LoadSuggestionEngine) — not in a View. A View that grows non-trivial branching or calculation is a signal to extract that logic into the library where `swift test` can reach it. (Views are still compile-checked in CI via `xcodebuild` on Xcode 26 — "can't be verified here" is not a reason to avoid touching them — but compilation is not behavior coverage.)

---

Optional parameters and default arguments should be scrutinised extremely carefully. They are a huge source of bugs (by omission). Prioritise correctness over backwards compatibility.

---

Formatting and lint are settled by `.swift-format` and `.swiftlint.yml` — don't relitigate them in review comments. Flag only violations, not preferences.

---

## Testing

### Core Principle

Tests verify behavior through public interfaces, not implementation details. Code can change entirely; tests shouldn't break unless behavior changed.

### Good Tests

Integration-style tests that exercise real code paths through public APIs. They describe _what_ the system does, not _how_.

```swift
// GOOD: Tests observable behavior through the public interface
@Test func loggedSetBecomesVisibleInSession() throws {
    let store = SessionStore(fixture: .seededSession)
    try store.log(SetResult(reps: 5, load: 142.5), for: exercise)
    #expect(store.session(for: exercise).completedSets.count == 1)
}
```

- Test behavior users/callers care about
- Use the public API only
- Survive internal refactors
- One logical assertion per test

### Bad Tests

Red flags:

- Mocking internal collaborators (your own types) — mock at system boundaries only (Google Sheets API, time, randomness)
- Testing private methods or asserting on call counts/order of internal calls
- Test breaks when refactoring without behavior change
- Test name describes HOW not WHAT
- Verifying through external means (poking at cache files) instead of through the interface
- Testing a trivial function (one-liner, simple mapping) where the test just mirrors the code — these add no confidence and break on any refactor

### Mocking

Mock at **system boundaries** only: the Sheets client, auth, time, randomness. **Never mock your own types or internal collaborators.** If something is hard to test without mocking internals, redesign the interface. Fixtures (`WorkoutTracker/Fixtures/`) are the preferred substitute for live sheet data.

### TDD Workflow: Vertical Slices

Do NOT write all tests first, then all implementation. That produces tests that verify _imagined_ behavior and are insensitive to real changes.

Correct approach — one test, one implementation, repeat:

```
RED→GREEN: test1→impl1
RED→GREEN: test2→impl2
RED→GREEN: test3→impl3
```

Each test responds to what you learned from the previous cycle. Never refactor while RED — get to GREEN first.

## Interface Design

### Deep Modules

Prefer deep modules: small interface, deep implementation. A few methods with simple params hiding complex logic behind them.

Avoid shallow modules: large interface with many methods that just pass through to thin implementation. When designing, ask: can I reduce the number of methods? Can I simplify the parameters? Can I hide more complexity inside?

### Design for Testability

1. **Accept dependencies, don't create them** — pass external dependencies in rather than constructing them internally.
2. **Return results, don't produce side effects** — a function that returns a value is easier to test than one that mutates state.
3. **Small surface area** — fewer methods = fewer tests needed, fewer params = simpler test setup.
