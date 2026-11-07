import Foundation

/// The Bar and plate sizes the Warm-up Ramp loads from. `bar` is the name `workout plates --bar` takes.
public struct PlateInventorySnapshot: Encodable, Equatable, Sendable {
    public let bar: String
    public let barPounds: Int
    public let plates: [Double]

    init(_ inventory: PlateInventory) {
        bar = inventory.bar.rawValue
        barPounds = inventory.bar.pounds
        plates = inventory.denominations.map(\.pounds)
    }
}

/// What goes on each side of the Bar to make a weight, and how far under it that lands.
public struct PlateLoadSnapshot: Encodable, Equatable, Sendable {
    public let perSide: [Double]
    public let reachable: Double
    public let remainder: Double

    init(_ load: PlateLoad) {
        perSide = load.perSide.map(\.pounds)
        reachable = load.reachable
        remainder = load.remainder
    }
}

public struct WarmupStepSnapshot: Encodable, Equatable, Sendable {
    public let reps: Int
    public let load: PlateLoadSnapshot
}

/// A Set's Warm-up Ramp. `top` says what it walks up to: `weight` is the card's pre-fill, in `pounds`.
/// `athletePicks`, `bodyweight`, and `timedSet` have no steps, and the sheet offers no ramp for the
/// last two. `topLoad` is nil when the Set has no weight, or the Bar alone outweighs it.
public struct WarmupRampReport: Encodable, Equatable, Sendable {
    public enum Top: String, Encodable, Sendable {
        case weight
        case athletePicks
        case bodyweight
        case timedSet
    }

    public let set: SetAddress
    public let exercise: String
    public let top: Top
    public let pounds: Double?
    public let topLoad: PlateLoadSnapshot?
    public let steps: [WarmupStepSnapshot]
    public let inventory: PlateInventorySnapshot

    init(set: SetAddress, exercise: String, top: WarmupTop, inventory: PlateInventory) {
        self.set = set
        self.exercise = exercise
        self.inventory = PlateInventorySnapshot(inventory)
        switch top {
        case .weight(let pounds):
            self.top = .weight
            self.pounds = pounds
            topLoad = PlateLoad(weighing: pounds, on: inventory).map(PlateLoadSnapshot.init)
            steps = WarmupRamp.make(top: .pounds(pounds), inventory: inventory).map {
                WarmupStepSnapshot(reps: $0.reps, load: PlateLoadSnapshot($0.load))
            }
            return
        case .athletePicks: self.top = .athletePicks
        case .bodyweight: self.top = .bodyweight
        case .timedSet: self.top = .timedSet
        }
        pounds = nil
        topLoad = nil
        steps = []
    }
}
