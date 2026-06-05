# ADR 0004: Liquid Glass Design System

**Status:** Superseded for Active Set Focus color direction  
**Date:** 2025-05-25

> Superseded note, 2026-05-26: the Active Set Focus redesign now uses the
> mint/emerald reference captured in
> `docs/superpowers/specs/2026-05-26-active-set-visual-direction.md`.
> Keep the Liquid Glass layering decisions from this ADR, but do not implement
> the older charcoal-to-warm-amber palette.

> Superseded note, 2026-06-05: the app has grown to roughly 36 Liquid
> Glass call sites across 12 views, so the original "single `Theme.swift` /
> no custom ViewModifiers" decision is superseded. All app-owned glass now
> routes through the `WorkoutGlass` helper, which keeps the repeated surface,
> button, container, and morphing vocabulary behind one seam while still calling
> Apple's native Liquid Glass APIs directly.

## Context

The app's UI was a bare `List`-based layout with no visual design system. With iOS 26 introducing Liquid Glass, we needed to decide how to adopt the new material language across the app — where to apply it, what sits behind it, and how to organize the styling code.

## Decision

### Background

A fixed full-bleed gradient (charcoal → warm amber) serves as the app's background. The gradient is constant — it does not shift based on session, week, or block context. This gives the glass material something rich to refract while keeping the implementation simple.

### Glass surfaces

Exercise cards are the primary glass surfaces. Each Exercise in a Session is rendered as a `.glassEffect(.regular, in: .rect(cornerRadius: 16))` card floating on the gradient. Sets within a card use a subtle lighter fill (sub-chip style) to signal future tappability, but are not themselves glass effects.

Card interior layout: bold exercise name at top → muted coach note below → set chips. No accent bars or extra decoration inside cards.

### Onboarding

Two-phase flow rendered as sequential glass cards (sign-in card, then URL-entry card) with morphing transitions (`glassEffectID`) between phases.

### Empty state

Custom glass card with dumbbell icon and a `.buttonStyle(.glass)` sync button — replaces `ContentUnavailableView`.

### Navigation and system chrome

Standard `NavigationStack` with `.navigationTitle` — iOS 26 handles the glass toolbar automatically. Pull-to-refresh uses the system default indicator.

### Deployment target

iOS 26 minimum. No `if #available` gates or fallback UI paths.

### Code organization

A single `Theme.swift` file holds all visual constants (gradient colors, corner radius, spacing). Views reference these directly. No custom ViewModifiers until the app grows to warrant them.

## Consequences

- Every view assumes iOS 26 — no backwards compatibility burden.
- The gradient palette can be swapped by editing one file (`Theme.swift`).
- Glass is applied selectively (exercise cards, onboarding cards, empty state) — not to every surface. This avoids the "glass everywhere" anti-pattern.
- Sets are styled as sub-chips anticipating the logging interaction, even though they're read-only today. This is a deliberate affordance choice, not premature implementation.
- System chrome (nav bar, refresh) is left to the platform — less code to maintain, consistent with iOS conventions.
