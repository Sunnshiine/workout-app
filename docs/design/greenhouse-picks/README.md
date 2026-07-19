# Greenhouse picks — visual ground truth

The winning renders ("picks") from the map [#408](https://github.com/Sunnshiine/workout-app/issues/408)
prototype tickets, consolidated onto `main` so agents and CI can compare implementation renders
against the locked design without checking out unmerged branches. **Picks only** — each ticket's
elimination trail stays on its source branch, which remains the design record.

Where a pick and prose disagree, [DESIGN.md](../../../DESIGN.md) wins (it adjudicated
cross-prototype conflicts after these captures were taken — e.g. final paper is the atmosphere
wash recipe, not the flat gradient visible in earlier picks).

| Screen / surface | Appearance | Pick | DESIGN.md section | Ticket · source branch |
| --- | --- | --- | --- | --- |
| Session stage (the living stage) | Day | [session-stage-a.png](session-stage-a.png) | §5.1 The Living Stage | [#413](https://github.com/Sunnshiine/workout-app/issues/413) · `claude/wayfinder-workout-app-zgwwra` |
| Session stage | Night | [session-stage-d.png](session-stage-d.png) | §5.1 The Living Stage | [#413](https://github.com/Sunnshiine/workout-app/issues/413) · `claude/wayfinder-workout-app-zgwwra` |
| Active Set Card input block | Day | [input-block3-c.png](input-block3-c.png) | §5.2 Active Set Card & input block | [#455](https://github.com/Sunnshiine/workout-app/issues/455) · `claude/wayfinder-issue-455-hwinsl` (`input-block3.html?variant=c`) |
| Superset stage | Day | [superset-stage4-a.png](superset-stage4-a.png) | §5.4 Superset stage | [#430](https://github.com/Sunnshiine/workout-app/issues/430) · `claude/wayfinder-issue-430-cwv5sw` |
| Superset stage | Night | [superset-stage4-b.png](superset-stage4-b.png) | §5.4 Superset stage | [#430](https://github.com/Sunnshiine/workout-app/issues/430) · `claude/wayfinder-issue-430-cwv5sw` |
| Exercise queue sheet (Superset containment) | Day | [superset-stage4-c.png](superset-stage4-c.png) | §5.4 Superset stage | [#430](https://github.com/Sunnshiine/workout-app/issues/430) · `claude/wayfinder-issue-430-cwv5sw` |
| Block grid, 2 days/week | Day | [block-grid-focus4-d-2d.png](block-grid-focus4-d-2d.png) | §5.5 Block grid | [#435](https://github.com/Sunnshiine/workout-app/issues/435) · `claude/wayfinder-issue-4rw7ty` (`block-grid-focus4.html?variant=d`) |
| Block grid, 3 days/week | Day | [block-grid-focus4-d-3d.png](block-grid-focus4-d-3d.png) | §5.5 Block grid | [#435](https://github.com/Sunnshiine/workout-app/issues/435) · `claude/wayfinder-issue-4rw7ty` |
| Block grid, 6 days/week | Day | [block-grid-focus4-d-6d.png](block-grid-focus4-d-6d.png) | §5.5 Block grid | [#435](https://github.com/Sunnshiine/workout-app/issues/435) · `claude/wayfinder-issue-4rw7ty` |
| Exercise History sheet (chip ledger, volume off) | Day | [exercise-history6-a.png](exercise-history6-a.png) | §5.6 Exercise History sheet | [#434](https://github.com/Sunnshiine/workout-app/issues/434) · `claude/wayfinder-issue-434-1lvw4x` |
| Exercise History sheet (volume chart on) | Day | [exercise-history6-b.png](exercise-history6-b.png) | §5.6 Exercise History sheet | [#434](https://github.com/Sunnshiine/workout-app/issues/434) · `claude/wayfinder-issue-434-1lvw4x` |
| Move On ceremony | Day | [sunbird-moments-a.png](sunbird-moments-a.png) | §5.7 Move On ceremony · §6 The Sunbird | [#414](https://github.com/Sunnshiine/workout-app/issues/414) · `claude/wayfinder-prototype-s96l3e` |
| Move On ceremony | Night | [sunbird-moments-d.png](sunbird-moments-d.png) | §5.7 Move On ceremony · §6 The Sunbird | [#414](https://github.com/Sunnshiine/workout-app/issues/414) · `claude/wayfinder-prototype-s96l3e` |
| Sheet-connect screen (flat calm) | Day | [sunbird-moments-c.png](sunbird-moments-c.png) | §5.8 Sheet-connect screen | [#414](https://github.com/Sunnshiine/workout-app/issues/414) · `claude/wayfinder-prototype-s96l3e` |
| Sheet-connect screen | Night | [sunbird-moments-e.png](sunbird-moments-e.png) | §5.8 Sheet-connect screen | [#414](https://github.com/Sunnshiine/workout-app/issues/414) · `claude/wayfinder-prototype-s96l3e` |
| Atmosphere — living paper washes | Day | [atmosphere2-i.png](atmosphere2-i.png) | §2 Living paper (atmosphere) | [#420](https://github.com/Sunnshiine/workout-app/issues/420) · `claude/wayfinder-issue-408-ay2ag4` (`atmosphere2.html?variant=i`) |
| Atmosphere — living paper washes | Night | [atmosphere2-k.png](atmosphere2-k.png) | §2 Living paper (atmosphere) | [#420](https://github.com/Sunnshiine/workout-app/issues/420) · `claude/wayfinder-issue-408-ay2ag4` (`atmosphere2.html?variant=k`) |

## Fidelity notes

- **Concept-era captures are deliberately excluded** (owner verdict on #470): the direction picks
  (#411), the night-edition recipe capture (#418), and the sunbird-role renders (#412) predate the
  component convergence and conflict with the final component picks above — the sunbird's ground
  truth is the #414 ceremony/connect rows. Those captures remain on their source branches as the
  design record; their decisions live on in DESIGN.md.
- **DESIGN.md wins over pixels.** DESIGN.md's prose + the token sheet
  ([greenhouse-theme-tokens.md](../greenhouse-theme-tokens.md)) override every capture here.
  Notable known deltas: session-stage picks predate the #455 input-block rework (pill row →
  weight-led stepper + rails); #422 adjudicated card padding, the 33pt Exercise name, and
  ceremony stats onto the shared surface after all captures.
- Exercise History night was never re-prototyped — it follows the #418 sheet recipe by rule
  (flagged for the build in #434).
