import Foundation

/// The one Exercise the queue sheet's Warm-up Ramp is for: the one on stage, while its first Pending
/// Set can walk up a Bar. Nil for bodyweight, a Timed Set, or no Pending Set, so nothing offers it.
struct WarmupEntry: Equatable, Sendable {
    let exerciseOrder: Int
    let exerciseTitle: String
    let setNumber: Int
    /// The Set's pre-fill. Nil leaves the athlete to pick a top.
    let prefill: Double?
}

@MainActor
extension WarmupEntry {
    init?(exercise: Exercise, history: LastPerformedLookupSnapshot) {
        let sets = exercise.sortedSets
        guard let index = sets.firstIndex(where: \.isPending) else { return nil }
        switch WarmupTop(for: sets[index], history: history) {
        case .weight(let pounds): prefill = pounds
        case .athletePicks: prefill = nil
        case .bodyweight, .timedSet: return nil
        }
        exerciseOrder = exercise.order
        exerciseTitle = exercise.exerciseName.base
        setNumber = index + 1
    }
}

/// What the Warm-up Ramp sheet shows for one Exercise: the load on the bar and every row of the walk.
struct WarmupRampPresentation: Equatable, Sendable {
    enum RowState: Equatable, Sendable {
        case finished
        case current
        case ahead
    }

    struct Row: Equatable, Identifiable, Sendable {
        let id: String
        let weight: String
        let detail: String
        let state: RowState
        let accessibilityLabel: String

        var accessibilityValue: String {
            switch state {
            case .finished: "Finished"
            case .current: "Current"
            case .ahead: ""
            }
        }
    }

    /// Plates on one side of the bar as drawn, heaviest first.
    let perSide: [PlateDenomination]
    let readout: String
    let caption: String
    /// Says why there is no walk to show, in place of the bar.
    let note: String?
    let rows: [Row]
    let setLabel: String
    /// The steps the rows above stand for, in row order, for a tap to name.
    let steps: [WarmupStep]

    init(entry: WarmupEntry, inventory: PlateInventory, walk: WarmupWalk) {
        let order = entry.exerciseOrder
        let top = entry.prefill ?? walk.pickedTop(forExerciseOrder: order)
        let setLabel = "Set \(entry.setNumber)"
        let topLoad = top.flatMap { PlateLoad(weighing: $0, on: inventory) }
        let steps = top.map { WarmupRamp.make(top: .pounds($0), inventory: inventory) } ?? []
        let finished = walk.finishedCount(of: steps, forExerciseOrder: order)
        let shown = steps.indices.contains(finished) ? steps[finished].load : topLoad

        self.setLabel = setLabel
        self.steps = steps
        perSide = shown?.perSide ?? []
        readout = Self.readout(perSide)
        caption = perSide.isEmpty ? inventory.bar.label : "a side on the \(inventory.bar.label) Bar"
        note = Self.note(top: top, topLoad: topLoad, setLabel: setLabel, bar: inventory.bar)
        let stepRows = steps.enumerated().map { index, step in
            Self.row(for: step, state: Self.state(of: index, finished: finished))
        }
        let setRowState = Self.state(of: steps.count, finished: finished)
        let setRow = topLoad.map { load in
            Self.setRow(asked: load.reachable + load.remainder, load: load, setLabel: setLabel, state: setRowState)
        }
        rows = stepRows + (setRow.map { [$0] } ?? [])
    }

    /// `2 × 45 + 25`: each size once, with its count where the side holds more than one.
    static func readout(_ perSide: [PlateDenomination]) -> String {
        guard !perSide.isEmpty else { return "Bar" }
        return PlateDenomination.allCases.compactMap { size in
            let count = perSide.count { $0 == size }
            switch count {
            case 0: return nil
            case 1: return size.label
            default: return "\(count) × \(size.label)"
            }
        }
        .joined(separator: " + ")
    }

    /// What a screen reader says for the drawn bar and its readout, as one thing.
    var barAccessibilityLabel: String {
        guard !perSide.isEmpty else { return "Bar, \(caption), nothing on it" }
        return "\(readout.replacingOccurrences(of: " × ", with: " times ").replacingOccurrences(of: " + ", with: " and ")) \(caption)"
    }

    private static func note(top: Double?, topLoad: PlateLoad?, setLabel: String, bar: Bar) -> String? {
        guard let top else { return "Pick \(setLabel)’s weight." }
        guard topLoad == nil else { return nil }
        return "\(setLabel) is \(Weight.pounds(top).label), lighter than the \(bar.label) Bar."
    }

    private static func state(of index: Int, finished: Int) -> RowState {
        if index < finished { return .finished }
        return index == finished ? .current : .ahead
    }

    private static func row(for step: WarmupStep, state: RowState) -> Row {
        let weight = Weight.pounds(step.load.reachable).label
        return Row(
            id: "warmup-step-\(weight)",
            weight: weight,
            detail: "× \(step.reps)",
            state: state,
            accessibilityLabel: "\(weight) pounds for \(step.reps) \(step.reps == 1 ? "rep" : "reps")"
        )
    }

    /// The Set the walk ends on. It is the coach's, so the row names it and never counts as a step.
    /// Where the Plate Inventory cannot make its weight, the row shows what it can and says so.
    private static func setRow(asked pounds: Double, load: PlateLoad, setLabel: String, state: RowState) -> Row {
        let weight = Weight.pounds(load.reachable).label
        let asked = Weight.pounds(pounds).label
        let isExact = load.remainder == 0
        return Row(
            id: "warmup-set",
            weight: weight,
            detail: isExact ? setLabel : "\(setLabel) is \(asked)",
            state: state,
            accessibilityLabel: isExact ? "\(setLabel), \(weight) pounds" : "\(setLabel) is \(asked) pounds, loads as \(weight)"
        )
    }
}

/// The weights the sheet's rail offers when a Set gave no top, resting on one plate a side.
enum WarmupTopRail {
    static let restingWeight = 135
    private static let weights = Array(stride(from: 50, through: 1000, by: 5))

    static func chips(picked: Double?) -> [ValueRailChip] {
        weights.map { weight in
            ValueRailChip(
                label: "\(weight)",
                isSelected: picked == Double(weight),
                isPrescribed: false,
                accessibilityIdentifier: "warmup-top-\(weight)"
            )
        }
    }

    static func selectedIndex(picked: Double?) -> Int {
        let resting = picked.map { Int($0) } ?? restingWeight
        return weights.firstIndex(of: resting) ?? 0
    }
}
