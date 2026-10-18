import Foundation

/// Whose the Live Activity is, which decides what a readback draws over and what ends it.
enum LiveActivityOwner: Equatable, Sendable {
    case nobody
    /// The stage's rest after a logged Set: its dates run the lifecycle.
    case rest(LiveActivityRestContent)
    /// A headless Dictation's Set, with no rest: it ends on the Dictation's result, staying on
    /// the Lock Screen a while for the athlete to read.
    case dictation
}

/// What a readback with no rest of its own does to the Live Activity. ActivityKit carries the
/// steps out in the app; the decision lives here, where `swift test` reaches it.
struct LiveActivityReadbackPlan: Equatable, Sendable {
    enum Canvas: Equatable, Sendable {
        /// Over the running rest, keeping its countdown.
        case overRest(LiveActivityRestContent)
        /// Over the Set alone.
        case alone

        /// When the system greys the activity out: over a rest, when the rest's would, so a
        /// readback leaves the rest's lifecycle as it was.
        var staleDate: Date? {
            switch self {
            case .overRest(let rest): LiveActivityInvalidationPolicy.postRestCapEndDate(for: rest)
            case .alone: nil
            }
        }
    }

    enum Step: Equatable, Sendable {
        case start
        case update
        /// Ends the activity on the readback, which stays on the Lock Screen a while to be read.
        case endShowing
    }

    let canvas: Canvas
    let steps: [Step]
    /// Whose the activity is once the steps are done.
    let owner: LiveActivityOwner

    /// A readback over the running rest keeps its countdown and leaves the rest its activity. A
    /// rest the readback may not ride is over, so the readback takes the activity as its own, as
    /// it takes one nobody here owns, and a final readback ends it. With no activity up, one
    /// starts for the readback.
    static func plan(
        isFinal: Bool,
        owner: LiveActivityOwner,
        activityIsUp: Bool,
        rides: (LiveActivityRestContent) -> Bool
    ) -> LiveActivityReadbackPlan {
        if case .rest(let rest) = owner, activityIsUp, rides(rest) {
            return LiveActivityReadbackPlan(canvas: .overRest(rest), steps: [.update], owner: owner)
        }
        return alone(isFinal: isFinal, startingOne: !activityIsUp)
    }

    /// The readback on an activity of its own. A final one over an activity already up needs no
    /// update before the end that shows it.
    private static func alone(isFinal: Bool, startingOne: Bool) -> LiveActivityReadbackPlan {
        var steps: [Step] = startingOne ? [.start] : []
        if isFinal {
            steps.append(.endShowing)
        } else if !startingOne {
            steps.append(.update)
        }
        return LiveActivityReadbackPlan(canvas: .alone, steps: steps, owner: isFinal ? .nobody : .dictation)
    }
}

/// What taking a readback off the Live Activity does, once the card has the Set.
enum LiveActivityReadbackWithdrawal: Equatable, Sendable {
    /// The rest shows as the stage left it.
    case restoreRest(LiveActivityRestContent)
    /// An activity the readback took as its own ends now.
    case end
    case nothing

    static func plan(owner: LiveActivityOwner, activityIsUp: Bool) -> LiveActivityReadbackWithdrawal {
        switch owner {
        case .rest(let rest) where activityIsUp: .restoreRest(rest)
        case .rest: .nothing
        case .dictation, .nobody: .end
        }
    }
}
