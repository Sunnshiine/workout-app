# Obsidian Color System

**Date:** 2026-05-25
**Status:** Approved

## Problem

The current gradient (`#262627` → `#995918`) reads as muddy and generic — dark-to-burnt-orange is a cliché in the gym-app category.

## Decision

Replace the background gradient with an near-flat obsidian void and introduce a single muted-gold accent. Liquid Glass cards provide all the visual richness; the background should stay out of the way.

## Color System

### Background Gradient

| Stop | Color | Hex |
|------|-------|-----|
| Top | `Color(red: 0.04, green: 0.04, blue: 0.04)` | `#0A0A0A` |
| Bottom | `Color(red: 0.07, green: 0.07, blue: 0.075)` | `#111213` |

Direction: top → bottom (unchanged).

### Accent

`Theme.accent = Color(red: 0.831, green: 0.686, blue: 0.216)` — antique gold `#D4AF37`

Used only on set index labels ("S1", "S2") and load/weight values in `SetChip`. Kept rare so it stays precious.

### Set Chip Refinements

| Property | Before | After |
|----------|--------|-------|
| Background | `white.opacity(0.08)` | `white.opacity(0.14)` |
| Stroke | none | `white.opacity(0.10)`, `0.5pt` |
| S# label color | `.foregroundStyle(.primary)` | `Theme.accent` |
| Load color | `.foregroundStyle(.secondary)` | `Theme.accent` |

## Files Changed

- `WorkoutTracker/Theme.swift` — gradient stops + accent constant
- `WorkoutTracker/Views/SetChip.swift` — chip styling + accent colors
