import Foundation

/// One plate size a gym can stock, heaviest first, by its weight in quarter pounds.
enum PlateDenomination: Int, CaseIterable, Hashable, Sendable {
    case fortyFive = 180
    case thirtyFive = 140
    case twentyFive = 100
    case ten = 40
    case five = 20
    case twoAndAHalf = 10

    var quarterPounds: Int { rawValue }

    var pounds: Double { Double(rawValue) / 4 }

    var label: String { Weight.pounds(pounds).label }

    init?(label: String) {
        guard let plate = Self.allCases.first(where: { $0.label == label }) else { return nil }
        self = plate
    }
}

/// The empty barbell a Plate Load goes on. Its own type and not a `Weight`, because a Bar is never
/// bodyweight.
enum Bar: String, CaseIterable, Hashable, Sendable {
    case standard = "45"
    case light = "35"
    case fifteenKilo = "15kg"

    /// Every weight here is in pounds, so a 15 kg Bar counts as its nearest whole pound.
    var pounds: Int {
        switch self {
        case .standard: 45
        case .light: 35
        case .fifteenKilo: 33
        }
    }

    var quarterPounds: Int { pounds * 4 }

    var label: String {
        switch self {
        case .standard, .light: "\(pounds) lb"
        case .fifteenKilo: "15 kg (\(pounds) lb)"
        }
    }
}

/// The Bar and the plate sizes the athlete's gym has. Local to the device, never in the Sheet.
struct PlateInventory: Equatable, Sendable {
    let bar: Bar
    let plates: Set<PlateDenomination>

    static let standard = PlateInventory(bar: .standard, plates: Set(PlateDenomination.allCases))

    /// The sizes the gym has, heaviest first.
    var denominations: [PlateDenomination] {
        PlateDenomination.allCases.filter(plates.contains)
    }

    func withBar(_ bar: Bar) -> PlateInventory {
        PlateInventory(bar: bar, plates: plates)
    }

    func with(_ plate: PlateDenomination, stocked: Bool) -> PlateInventory {
        PlateInventory(bar: bar, plates: stocked ? plates.union([plate]) : plates.subtracting([plate]))
    }
}

extension PlateInventory {
    /// The plate sizes as `AppDefaults` stores them: `45,25,10`, and an empty string for none.
    var storedPlates: String {
        denominations.map(\.label).joined(separator: ",")
    }

    /// A stored size this build does not know is dropped. A value nothing stored yet keeps the full
    /// list, so a new install has every plate.
    init(storedBar: String?, storedPlates: String?) {
        bar = storedBar.flatMap(Bar.init(rawValue:)) ?? Self.standard.bar
        plates =
            storedPlates.map { stored in
                Set(stored.split(separator: ",").compactMap { PlateDenomination(label: String($0)) })
            } ?? Self.standard.plates
    }
}
