import Foundation

/// What goes on each side of the Bar to make a weight. A Plate Load the inventory cannot make exactly
/// is the nearest one below it, and `remainder` says by how much.
struct PlateLoad: Equatable, Sendable {
    /// Heaviest first, the order the plates go on from the collar.
    let perSide: [PlateDenomination]
    let reachable: Double
    let remainder: Double

    /// Nothing on a barbell weighs more, so a heavier weight is a typo and is not worth building.
    static let heaviestPounds = 2000.0

    /// Nil for a weight lighter than the empty Bar, or past `heaviestPounds`.
    init?(weighing pounds: Double, on inventory: PlateInventory) {
        guard pounds <= Self.heaviestPounds else { return nil }
        let asked = Int((pounds * 4).rounded(.down))
        guard asked >= inventory.bar.quarterPounds else { return nil }
        perSide = Self.plates(perSideOf: asked, on: inventory)
        let reachableUnits = inventory.bar.quarterPounds + 2 * perSide.reduce(0) { $0 + $1.quarterPounds }
        reachable = Double(reachableUnits) / 4
        remainder = pounds - reachable
    }

    /// Takes the heaviest plate that still leaves a weight the gym can build. That is the greedy load
    /// wherever greedy lands exactly, and finds 25 + 25 for a gym of 45s and 25s where greedy stops
    /// at one 45.
    private static func plates(perSideOf asked: Int, on inventory: PlateInventory) -> [PlateDenomination] {
        let sizes = inventory.denominations
        let budget = (asked - inventory.bar.quarterPounds) / 2
        var buildable = [Bool](repeating: false, count: budget + 1)
        buildable[0] = true
        for weight in stride(from: 1, through: budget, by: 1) {
            buildable[weight] = sizes.contains { $0.quarterPounds <= weight && buildable[weight - $0.quarterPounds] }
        }

        var left = buildable.lastIndex(of: true) ?? 0
        var perSide: [PlateDenomination] = []
        while let plate = sizes.first(where: { left > 0 && $0.quarterPounds <= left && buildable[left - $0.quarterPounds] }) {
            perSide.append(plate)
            left -= plate.quarterPounds
        }
        return perSide
    }
}
