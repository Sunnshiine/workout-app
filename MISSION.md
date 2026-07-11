# Mission: The interfaces of this codebase's deep modules

## Why
This app is deliberately built from deep modules, and the owner architects features and
directs agent-driven implementation rather than reading every implementation. Knowing each
module's interface cold — what a caller must know, no more — is what lets them place new
features at the right seam, judge architecture changes, and spot when a module is going
shallow.

## Success looks like
- Given a new feature idea, name which module's interface it touches and what (if anything)
  must be added to that interface — without opening the implementation.
- Draw the module map from memory: the modules, their front-door types, and which interfaces
  depend on which.
- For any module, state its contract in one sentence: what a caller provides, what it gets
  back, and the invariants/error modes that aren't visible in the type signature.
- Evaluate a proposed change with the repo's vocabulary: does it deepen a module, add a
  hypothetical seam, or leak implementation into an interface?

## Constraints
- Visual learner — every lesson leads with a diagram; prose supports the picture.
- Stay above the waterline: interfaces only. No walkthroughs of implementation internals.
- Short lessons; one module or one relationship at a time.

## Out of scope
- Implementation internals of the modules (parsing algorithms, sync mechanics, cache format).
- Swift language instruction — the user works in this codebase already.
- SwiftUI view code — Views are consumers of the interfaces, not modules under study.
