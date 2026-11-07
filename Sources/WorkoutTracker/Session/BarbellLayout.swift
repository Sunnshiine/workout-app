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
            return Plate(id: "\(size.rawValue)-\(ordinal)", offset: offset, thickness: thickness, height: size.drawnHeight)
        }
    }
}

extension PlateDenomination {
    /// Shares of a 45's diameter, from the plates a commercial gym stocks.
    fileprivate var drawnHeight: Double {
        switch self {
        case .fortyFive: 1
        case .thirtyFive: 0.86
        case .twentyFive: 0.7
        case .ten: 0.52
        case .five: 0.42
        case .twoAndAHalf: 0.34
        }
    }

    /// Shares of a 45's thickness.
    fileprivate var drawnThickness: Double {
        switch self {
        case .fortyFive: 1
        case .thirtyFive: 0.86
        case .twentyFive: 0.72
        case .ten: 0.5
        case .five: 0.4
        case .twoAndAHalf: 0.3
        }
    }
}
