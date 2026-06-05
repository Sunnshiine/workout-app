# Move On Celebration Prototype

Question: Which redesigned Move On Celebration direction feels worth seeing after a hard Session?

This is throwaway prototype code. It lives next to `MoveOnCelebrationView.swift` for context, but it is not part of the iOS app target.

Run:

```bash
uv run python -m http.server 4173 --directory WorkoutTracker/Views/MoveOnCelebrationPrototype
```

Open:

```text
http://127.0.0.1:4174/?variant=F3
```

Variants:

- F3, Quiet Finish: keeps F2's timing rows and nucleus motion, makes the fun quote the main message, and removes the reverse-pyramid / Exercise-card noise.
- C2, Workout Route: makes the whole Session visible with an animated route draw and Exercise checkpoints.
- E2, Plate Swipe: turns Plate Stack into a swipeable Exercise object with first Set Log times.
- F2, Night Finish: keeps the top-left TFN mark, Started / Elapsed / Moved On rows, and only Sets / Exercises / Left in the bottom summary.
- H, Route Stack: combines F's shell, E's swipeable Exercise card, and C's route context.

Verdict placeholder: pick one variant, or combine specific pieces, then delete this prototype and implement the final SwiftUI version properly.
