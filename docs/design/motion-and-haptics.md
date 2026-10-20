# Design System: Motion & Haptics (DESIGN.md §7)

Part of [DESIGN.md](../../DESIGN.md) §7, whose rule this serves: custom motion is confined to
three growth moments on the wing ease, and all chrome rides stock system springs. A § number
names a section of DESIGN.md or of one of its component files, which keep its numbering.

1. **Leaf inks on log** — 0.42s; a dashed Skip draws in the same language.
   On a Superset the leaf inks at once under its bud, and the bud lifts
   off over the 0.26s before the partner's bud wakes, so the logged node
   never empties and the stage never shows two cream leaves.
2. **Next leaf wakes** — inside the leaf's tail (starts 0.26s in, runs
   0.34s). **One Log, One Fill:** the transition must read as the cream
   leaf waking (logging then inks it solid), never a second leaf filling.
3. **Ceremony** — stem 1.0s, 0.10s beat, bird drops 0.35s (≈1.5s, Brisk).

Haptics are **Crisp, silent-chrome, semantic-only**: RPE detent tick
0.35/0.85 · log 1.0/0.65 · skip dud 0.45/0.15 · stepper ± 0.45/0.80 (the
floor hits the dud) · one identical swell-and-peak Move On pattern timed to
the ceremony · none on form fields. Hold-to-skip: reveal 250ms, commit
850ms, retreat 0.2s; logged-state hold 900ms. A Skipped Set's capsule takes
no hold: a tap logs it, and its More menu clears it (#820).

**Reduced motion** turns the leaf ink and the bud wake into 0.2s
crossfades to their end states, so both appear in place. The bud's
crossfade starts as the leaf's ends, so the stage never shows two cream
leaves. A Superset bud lifts off its ink in the same 0.2s, before its
partner's bud wakes. The ceremony fades in fully grown. Haptics are unaffected.

Reduce Motion leaves the Active Set Card unchanged (§5.2). Its box holds
still, and what moves inside it answers the athlete's own finger.
