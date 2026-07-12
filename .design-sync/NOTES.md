# design-sync notes

- This repo is a **Swift/SwiftUI iOS app** — there is no web design system to convert.
  The standard design-sync converter pipeline does not apply here; do not look for a
  Storybook or a JS `dist/`. The only `package.json` is Sandcastle agent tooling.
- The pinned project (`Workout App Redesign`, cc7000ec-0e2d-490a-b64c-e43712062e8c) is a
  **hand-authored, guidelines-only** Claude Design project created 2026-07-04 to seed a
  full UI redesign. It carries no components and no `_ds_sync.json` anchor (intentional —
  there is no converter build to anchor to).
- Source of truth for its content: `.design-sync/guidelines-project/` in this repo
  (README.md + guidelines/ + styles.css). Edit there and re-upload; content derives from
  CONTEXT.md, PRODUCT.md, and DESIGN.md.
- Deliberate scope decision: current Theme.swift / DESIGN.md visual tokens were NOT
  uploaded as constraints — the user wants a full redesign. Durable product rules
  (domain language, brand personality, anti-references, iOS-native constraints) are in;
  the current palette/components appear only in `guidelines/current-app-reference.md`
  marked reference-only.
