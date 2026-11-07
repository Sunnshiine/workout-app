import Foundation

/// Where each plate sits on a sleeve, measured from the collar. Plates keep their real proportions and
/// squeeze together only when a load would otherwise run off the sleeve's end, which stays in view.
struct BarbellLayout: Equatable, Sendable {
    struct Plate: Equatable, Identifiable, Sendable {
        let id: String
        let offset: Double
        let thickness: Double
        /// A share of the 45's height.
        let height: Double
    }

    private static let fullThickness = 17.0
    private static let gap = 1.5

    let plates: [Plate]

    init(perSide: [PlateDenomination], sleeveLength: Double) {
        let usable = sleeveLength * 0.9
        let gaps = Double(max(perSide.count - 1, 0)) * Self.gap
        let natural = perSide.reduce(0) { $0 + $1.drawnThickness * Self.fullThickness }
        let squeeze = min(1, (usable - gaps) / max(natural, 1))
        var offset = 0.0
        var seen: [PlateDenomination: Int] = [:]
        plates = perSide.map { size in
            let thickness = size.drawnThickness * Self.fullThickness * squeeze
            let ordinal = seen[size, default: 0]
            seen[size] = ordinal + 1
            defer { offset += thickness + Self.gap }
            return Plate(id: "\(size.label)-\(ordinal)", offset: offset, thickness: thickness, height: size.drawnHeight)
        }
    }
}

extension PlateDenomination {
    /// A share of a 45's diameter, falling off slower than the weight so a 2.5 still reads as a plate.
    fileprivate var drawnHeight: Double { 0.3 + 0.7 * shareOfAFortyFive }

    /// A share of a 45's thickness.
    fileprivate var drawnThickness: Double { 0.25 + 0.75 * shareOfAFortyFive }

    private var shareOfAFortyFive: Double { pounds / Self.fortyFive.pounds }
}
