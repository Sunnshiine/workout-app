# Design System: Gestures (DESIGN.md §9)

Part of [DESIGN.md](../../DESIGN.md) §9, whose Named Rules this file holds, as the §5 specs hold
theirs. A § number names a section of DESIGN.md or of one of its component files, which keep its
numbering. The values here are `Theme.Gesture` in `Sources/WorkoutTracker/Theme.swift` and token
sheet §10. Every rule below was written under the operator's brief of 2026-11-08: "Design pass.
Read the existing DESIGN.md and add a Gestures section covering which surfaces are draggable or
swipeable, dismiss thresholds, velocity and spring rules, rubber-banding, haptic moments, and
reduced-motion behavior."

<!-- doc-symbols: not-in-tree interpolatingSpring initialVelocity accessibilityAdjustableAction -->

## Named Rules

A gesture is direct manipulation. While the finger is down the surface is the finger; when it
lifts, a spring carrying the finger's speed finishes the move. §7 governs what a tap sets in
motion, and these rules govern what a finger moves.

**The Finger Owns the Track.** While the finger is down, a dragged surface moves 1:1 with it, from
where it was grabbed, with no animation on the tracked value. Per-frame drag state lives in the
view's gesture state, never in a store round-trip per frame. (Operator, 2026-11-08.)

**The Release Carries the Speed.** On lift, the surface settles on a spring seeded with the
gesture's release velocity, normalised by the distance left to the target, to the detent nearest
its projected rest. The projection is Apple's, the velocity in points per millisecond times
`d / (1 - d)`, with d the deceleration rate. The rails take `Theme.Gesture.railDecelerationRate`
(0.99), so a flick throws a few detents, not the whole scale. (Operator, 2026-11-08.)

**Detents Land Still.** A surface that lands on a value lands critically damped, bounce 0, in
about 0.3 s (`Theme.Gesture.release`), so the value reads settled. Bounce is reserved for a thrown
surface that leaves, and none ships today. (Operator, 2026-11-08.)

**Distance or Speed Commits.** A gesture that commits (a dismiss, a skip, a reveal) commits past
about half its travel, or on a release faster than 500 pt/s toward the commit. Otherwise it snaps
back on a fast critically damped spring, about 0.2 s (`Theme.Gesture.snapBack`), because a slow
snap-back reads as the app disagreeing. (Operator, 2026-11-08.)

**Edges Resist.** Past its first or last detent a surface follows on Apple's rubber-band curve,
`(x * d * c) / (d + c * abs(x))` with d the track's width and c `Theme.Gesture.rubberBandConstant`
(0.55), never a hard stop, and springs back to the end detent on release. (Operator, 2026-11-08.)

**Catch It Mid-Flight.** Every gesture-driven settle is a spring from the on-screen value. A touch
during a settle grabs the surface where it is. Nothing a gesture touches rides a fixed-duration
curve or a keyframe. §7's press spring is unchanged. (Operator, 2026-11-08.)

**Intent Before Direction.** A drag claims its axis after 10 pt (`Theme.Gesture.hysteresis`) and
yields the other axis to the scroll or sheet beneath it. A tap stays a tap, and a drag's release
never also fires the cell under the lifted finger. (Operator, 2026-11-08.)

**Every Gesture Has a Button.** No action is gesture-only. Each has a tap target, a button, or a
VoiceOver action. The rails take VoiceOver's adjustable action, and hold-to-skip keeps the Skip
action that already ships. (Operator, 2026-11-08.)

**Haptics Mark Commits.** A gesture plays its haptic on the frame a value or state commits: a
detent crossing the centre (the rail's detent tick, §7), a skip committing, a threshold passing.
Never per frame, and never on the settle's end. §7's semantic-only, silent-chrome rule holds, and
this section adds no haptic pattern. (Operator, 2026-11-08.)

**Reduce Motion Keeps the Finger.** Tracking stays 1:1, because the athlete makes that motion.
What goes is the projection (a release lands on the detent nearest where the finger lifted), any
bounce, and decorative motion around a gesture. The settle is one critically damped move of at
most 0.2 s, the snap-back spring. Haptics are unaffected. (Operator, 2026-11-08.)

**System Surfaces Keep System Gestures.** Sheets keep their detents and the system drag, with no
hand-rolled sheet physics (§7, §8), and the spec names each sheet's detents. A sheet with a
decision pending refuses interactive dismiss, as the Destructive Confirmation Card already does
(§5.9). Navigation, menus, text fields, and the Lens wheel's scroll keep iOS's gestures.
(Operator, 2026-11-08.)

**No Pull to Refresh.** `PRODUCT.md`'s "Sync automatically, recover manually" puts manual sync in
Settings (§5.9 Settings Own Manual Sync Rule), so no screen pulls to refresh. (Operator,
2026-11-08.)

## Values

| Value | Amount | Token | Rule |
| --- | --- | --- | --- |
| Hysteresis | 10 pt | `Theme.Gesture.hysteresis` | §9 Intent Before Direction |
| Rail projection rate | 0.99 | `Theme.Gesture.railDecelerationRate` | §9 The Release Carries the Speed |
| Release spring | response 0.3 s, bounce 0 | `Theme.Gesture.release` | §9 Detents Land Still |
| Snap-back spring | response 0.2 s, bounce 0 | `Theme.Gesture.snapBack` | §9 Distance or Speed Commits |
| Rubber-band constant | 0.55 | `Theme.Gesture.rubberBandConstant` | §9 Edges Resist |
| Commit threshold | half the travel, or 500 pt/s toward the commit | prose, until a gesture uses it | §9 Distance or Speed Commits |
| Reduce Motion settle | the snap-back spring, at most 0.2 s and critically damped | `Theme.Gesture.snapBack` | §9 Reduce Motion Keeps the Finger |

### The release, in SwiftUI

The settle is `.interpolatingSpring(duration:bounce:initialVelocity:)`, with the duration the
spring's response, the bounce 0, and `initialVelocity` the release velocity divided by the
distance left to the target, so a finger moving 50 pt/s with 100 pt to go seeds 0.5. The target
is the detent nearest the projected rest, `position + v / 1000 * d / (1 - d)`, with v the release
velocity in points per second and d the deceleration rate. Past the first or last detent the
surface follows `(x * d * 0.55) / (d + 0.55 * abs(x))`, with x the overshoot and d the track's
width. A touch during the settle grabs the surface where it is, so the spring starts from the
on-screen value, never the target. Under Reduce Motion the projection goes, and the release lands
on the detent nearest where the finger lifted, on the snap-back spring.

## Surfaces

What answers a finger today, read from the code on 2026-11-08. Where today's code departs from a
§9 rule, the rule stands and the gesture pass fixes the code.

| Surface | Where | Gesture today | Alternative | Haptic | Against §9 |
| --- | --- | --- | --- | --- | --- |
| Reps and RPE rails | `App/Views/ValueRail.swift` | A horizontal drag of 10 pt or more moves the selection one detent per 48 pt cell from where the drag began. Between detents the strip holds still, and each detent recentres it on a 0.22 s snappy spring, which bounces 0.15. A drag's release does not fire the cell under the lifted finger. | Each cell is a button labelled with its value. No adjustable action yet. | The detent tick on each detent moved, and on a tap. | Steps detent by detent instead of tracking 1:1. The recentre bounces 0.15 and takes no release velocity, and a drag begun during it anchors on the selected value, not the strip on screen. No projection, and a hard stop past the ends. No adjustable action. Opportunities 1 and 3. |
| Log capsule | `App/Views/SmartValuePills.swift`, `Sources/WorkoutTracker/Session/HoldToSkipGesture.swift` | The §7 press sinks it to 0.97. Hold-to-skip fills linearly from the 250 ms reveal to the 850 ms commit (900 ms on a logged Set) and retreats over 0.2 s on release. A finger that travels past 44 pt cancels the press. A release before the reveal logs. | A tap logs. VoiceOver's Skip action skips. | The log haptic on a log, the skip dud on the commit. | Holds. The fill shows time passing, so linear is right. |
| Mic | `App/Views/ActiveSetCard.swift` | Press and hold to speak, and the release finishes. | VoiceOver's activation starts listening and the next one finishes. | Dictation's start and outcome haptics. | Holds. |
| Weight steppers | `App/Views/WeightStepperButton.swift` | A tap, with the §7 press. | They are buttons. | The stepper tick, the dud at the floor. | Holds. |
| Weight | `App/Views/SmartValuePills.swift` | A tap raises the keyboard. | It is a button, and Done folds the keyboard. | None, a form field. | Holds. |
| Lens wheel | `App/Views/SessionQueueSheet.swift` | The system scroll, with `WheelSnap` resting a row's centre on the wheel's. A tap jumps. | Each row is a button. | None. | Holds (System Surfaces Keep System Gestures). Reduce Motion draws every row at full size. |
| Held card after a Spoken Set | `App/Views/ActiveSetCard.swift` | Any touch moves the card on. | Clear, in the head's menu. | None. | Holds. |
| Stage background | `App/Views/SessionStageView.swift` | A tap folds the keyboard (§5.2 Inert-Space All-Clear Rule). | Done, on the keyboard toolbar. | None. | Holds. |

### Sheets

Every sheet keeps `presentationDetents` and the system drag.

| Sheet | Where | Detents | Interactive dismiss |
| --- | --- | --- | --- |
| This Session | `App/Views/SessionQueueSheet.swift` | `.medium` | Yes |
| Exercise History | `App/Views/ExerciseHistorySheet.swift` | `.medium`, `.large` | Yes |
| Set Flag | `App/Views/SetFlagSheet.swift` | `.medium`, `.large`, with the selection bound | Yes, and it drops the typed words (Opportunity 2) |
| Sheet tab | `App/Views/BlockOverviewView.swift` | `.large` | Yes |
| Settings | `App/Views/SessionView.swift`, `App/Views/BlockOverviewView.swift` | The system default | Yes, except while the Destructive Confirmation card shows |
| Destructive Confirmation card | `App/Views/DestructiveConfirmation.swift` | Drawn in place over its sheet | Refused while the card shows (`interactiveDismissDisabled`) |

No screen pulls to refresh (§9 No Pull to Refresh, §5.9 Settings Own Manual Sync Rule).

## Opportunities

Pass 2 surveyed every screen on 2026-11-08 and filmed the existing gestures on the simulator at
1c5d9dad. Each candidate went through four gates: frequency, purpose, speed, and function. Three
gesture gates came after them. Would it fight a system gesture, or the sheet or scroll beneath it?
Would a chalky one-handed thumb hit it by accident? Does it have a tap, a button, or a VoiceOver
alternative? Rank is leverage: how often the athlete meets the surface, and how far it sits from §9.
A backticked lowercase name in Evidence or Holding, such as `rail-slow`, is a take filmed in the PR
that added this section.

| Rank | Surface | Where | Today | Against §9 | Proposed | Alternative | Reduce Motion | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Reps and RPE rails | `App/Views/ValueRail.swift:61`, `:37` | Steps one detent per 48 pt of drag and holds still between detents. Each step recentres on a 0.22 s snappy spring with bounce 0.15. A release adds nothing, a drag during a settle starts from the selected value, and the ends are hard stops. | The Finger Owns the Track, The Release Carries the Speed, Detents Land Still, Edges Resist, Catch It Mid-Flight. | Track 1:1. The strip's offset is its settled offset plus the drag's translation in gesture state, with no animation while the finger is down. The value commits, and the detent tick plays, as each detent crosses the centre. On lift, land on the detent nearest `position + v / 1000 * 0.99 / 0.01` (`Theme.Gesture.railDecelerationRate`), on `Theme.Gesture.release` (0.3 s, bounce 0) seeded with v over the distance left. Past an end, follow the rubber-band with c `Theme.Gesture.rubberBandConstant` (0.55) and d the track's width, and spring back on `Theme.Gesture.snapBack` (0.2 s, bounce 0). A drag during the settle starts from the on-screen offset. The axis is claimed after `Theme.Gesture.hysteresis` (10 pt). The math goes in `ValueRailLayout`, where `swift test` reaches it. | Each cell stays a button. Rank 3 adds the adjustable action. | Tracking stays 1:1. A release lands on the detent nearest the lift, on `Theme.Gesture.snapBack`, with no projection. | `rail-slow`: the strip hops a whole cell, then sits still while the finger keeps moving. `rail-flick`: a fast flick throws exactly one detent, where the projection at 0.99 adds 99 pt for each 1000 pt/s of release, two detents. `rail-past-end`: the strip stops dead for the last 128 pt of a 320 pt drag. |
| 2 | Set Flag sheet | `App/Views/SessionStageView.swift:93` | One downward drag, or a tap above the sheet, closes it and drops the typed words. Reopened, the field shows its placeholder. | System Surfaces Keep System Gestures keeps the drag, but the drag costs the athlete's words. | No new gesture. Keep the system drag, and keep each Set's `SetFlagDraft` while the Session is open, cleared on Raise. Refusing interactive dismiss instead would leave a sheet with no close button and no way out. | The tap above the sheet, which also closes it. With the draft kept, neither way loses anything. | Unchanged. It is a system sheet. | `flag-dismiss`: "left hip pinch" with Pain, one drag down, and the reopened sheet reads "What should your coach know?". A tap above the medium sheet did the same, driven once by hand. |
| 3 | Rails under VoiceOver | `App/Views/ValueRail.swift:54` | Each cell is its own button, so reaching a value means swiping through every cell, including those drawn off screen. | Every Gesture Has a Button names the adjustable action for the rails, and none ships. | One element per rail, labelled Reps or RPE, with the selection as its value. `accessibilityAdjustableAction` steps one detent and plays the detent tick. | This row is the alternative. | Not applicable. | The accessibility tree lists Reps 3 through Reps 10 as separate buttons, the first at x −6. |

**Rejected.** Each candidate is listed with the gate that killed it.

- Pull to refresh on any screen: §9 No Pull to Refresh.
- Swipe between Sets on the card. *System gesture*: it fights the rails' horizontal axis. *Chalky
  thumb*: a stray swipe changes which Set gets logged.
- Swipe the rest pill away. *Purpose*: the rest pill has no action to commit. *Alternative*: it
  would be gesture-only.
- Drag to reorder Exercises or Sets. *Function*: the order is the coach's Sheet order, and
  `CONTEXT.md` defines no athlete order.
- Swipe actions on This Session's rows. *System gesture*: the wheel is a scroll view with
  `WheelSnap`, not a list, so a row swipe fights the scroll and the sheet's drag.
- Press and hold a weight stepper to repeat. *Speed*: steps of 2.5 or 5 and the prefill keep a
  change to one or two taps, and the keyboard covers big jumps. *Chalky thumb*: a resting thumb
  would run the weight away.
- Swipe up on the queue bar to open This Session. *System gesture*: it fights the home indicator.
- Scrub the weight by dragging it. *Chalky thumb*: an accidental drag changes the weight that gets
  logged.
- Swipe down to fold the keyboard on the stage. *Speed*: a tap on the stage already folds it (§5.2
  Inert-Space All-Clear Rule).
- Hold to end the effort countdown. *Function*: ADR-0023 decided that a tap ends it.

**Holding.** Hold-to-skip on the Log capsule (`hold-full`, `hold-early`, `hold-slide`), the sheet
detents and drag (`queue-dismiss`, `queue-pull-up`, `history-dismiss`, `history-to-large`), and the
Lens wheel's flick (`wheel-flick`) behave as the Surfaces table says. They need no change.

**Verdict.** The rails are the single highest-leverage item. The athlete drags the reps and RPE
rails whenever a Set departs from its prescription, with chalk on their hands and the bar waiting.
Today the strip answers in 48 pt jumps, ignores the throw, and stops dead at the ends, which breaks
five of §9's rules on the surface the athlete drags most. The fix needs no new token, because every
value it uses is in `Theme.Gesture`. Its math lands in `ValueRailLayout`, where `swift test` pins
it.
