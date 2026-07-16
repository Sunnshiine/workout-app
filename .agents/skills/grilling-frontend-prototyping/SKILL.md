---
name: grilling-frontend-prototyping
description: Converge on a frontend look through rounds of prototypes and grilling verdicts. Use when the user wants to iterate on UI/visual taste against concrete variants, or a wayfinder prototype ticket names this skill.
---

Run a `/grilling` session, using the `/prototype` skill — each question is asked with prototypes, not words:

- Each round, build 5 radically different prototypes of the current design
  question into one live mocked app, updated in place each round. Let the
  `/prototype` skill pick the artifact for the question — don't assume a
  format. Its render target decides the medium (an HTML render, a device
  build, whatever fits); build the round in that medium.
- A variant switcher names each design and moves between them — ←/→ to cycle,
  restyling the mocked app live — using whatever switcher the chosen target
  provides (the HTML render's floating bottom bar, a device build's on-screen
  switcher). When the design has meaningful states (an inbox: full vs empty),
  add controls that toggle the mock between them.
- The grilling walks down the visual design tree, each verdict zooming in
  one level: the overall design, then component groups, then individual
  components — until the user has designed the entire feature in detail.
