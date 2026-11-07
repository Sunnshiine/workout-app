import Foundation

/// How far up each Exercise's Warm-up Ramp the athlete has walked in the Session on stage, and the top
/// they picked where the Set gave none. Lives only as long as that Session stays on stage. The walk is
/// held as the heaviest weight lifted and not a row number, so a changed Bar leaves it true.
struct WarmupWalk: Equatable, Sendable {
    private var walkedThrough: [Int: Double] = [:]
    private var pickedTops: [Int: Double] = [:]

    func pickedTop(forExerciseOrder order: Int) -> Double? {
        pickedTops[order]
    }

    mutating func pick(top: Double, forExerciseOrder order: Int) {
        pickedTops[order] = top
    }

    /// How many of `steps`, lightest first, the athlete has walked through.
    func finishedCount(of steps: [WarmupStep], forExerciseOrder order: Int) -> Int {
        guard let walked = walkedThrough[order] else { return 0 }
        return steps.count { $0.load.reachable <= walked }
    }

    /// The athlete tapped the row at `index`, where `steps.count` is the Set the walk ends on. A row
    /// ahead walks them there, finishing every step below it. A Finished step goes back to being
    /// current, taking every step above it along.
    mutating func tap(rowAt index: Int, of steps: [WarmupStep], forExerciseOrder order: Int) {
        if index < finishedCount(of: steps, forExerciseOrder: order) {
            walkedThrough[order] = index == 0 ? nil : steps[index - 1].load.reachable
        } else if steps.indices.contains(index) {
            walkedThrough[order] = steps[index].load.reachable
        } else {
            walkedThrough[order] = steps.last?.load.reachable
        }
    }
}
