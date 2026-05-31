# WorkoutTracker

A mobile client for powerlifting athletes that surfaces and logs workouts from a
coach-managed Google Sheet. The Sheet is the single source of truth; the app is a
read-write client with a local cache.

## Getting started

Open `WorkoutTracker.xcodeproj` in Xcode and run the `WorkoutTracker` scheme on the
iPhone 17 Pro simulator — it launches against deterministic local fixtures, not live data.

```bash
swift test   # fast unit + component tests, no Secrets.xcconfig needed
```

## Docs

- **`AGENTS.md`** / **`CLAUDE.md`** — build, test, and contribution guide for AI agents
- **`CONTEXT.md`** — domain glossary (Block, Session, Set Log, Load Suggestion …)
- **`docs/adr/`** — architecture decision records
