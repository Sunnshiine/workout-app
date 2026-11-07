import Foundation

/// A weight on a Meet's bar. A Meet runs in kilograms and a Set Log in pounds, so this type stays
/// inside the Meet and never meets `Weight`. Whole hundredths keep 2.5 and 0.5 exact.
struct Kilograms: Hashable, Comparable, Sendable {
    let hundredths: Int

    init(hundredths: Int) {
        self.hundredths = hundredths
    }

    init(whole: Int) {
        self.init(hundredths: whole * 100)
    }

    /// Reads `187.5`, `190`, or a keyboard's `187,5`. Rejects anything but a positive weight of at
    /// most two decimals and four whole digits, which is more than any bar holds.
    init?(parsing text: String) {
        guard let match = text.trimmed.wholeMatch(of: /(\d{1,4})(?:[.,](\d{0,2}))?/.asciiOnlyDigits()), let whole = Int(match.1) else {
            return nil
        }
        let decimals = String(match.2 ?? "").padding(toLength: 2, withPad: "0", startingAt: 0)
        let hundredths = whole * 100 + (Int(decimals) ?? 0)
        guard hundredths > 0 else { return nil }
        self.init(hundredths: hundredths)
    }

    static func < (lhs: Kilograms, rhs: Kilograms) -> Bool {
        lhs.hundredths < rhs.hundredths
    }

    static func + (lhs: Kilograms, rhs: Kilograms) -> Kilograms {
        Kilograms(hundredths: lhs.hundredths + rhs.hundredths)
    }

    func subtracting(_ step: Kilograms, floor: Kilograms) -> Kilograms {
        Swift.max(floor, Kilograms(hundredths: hundredths - step.hundredths))
    }

    func isMultiple(of step: Kilograms) -> Bool {
        hundredths.isMultiple(of: step.hundredths)
    }

    /// `187.5`, `190`, `182.25`: no trailing zeros, because a platform board shows none.
    var numeral: String {
        let fraction = hundredths % 100
        if fraction == 0 { return "\(hundredths / 100)" }
        if fraction.isMultiple(of: 10) { return "\(hundredths / 100).\(fraction / 10)" }
        return "\(hundredths / 100).\(String(format: "%02d", fraction))"
    }

    var label: String { "\(numeral) kg" }

    /// To the tenth of a pound, as the USAPL rulebook prints 130 kg as 286.6 lb (5.3.14.2's example).
    var poundsTenths: Int {
        Int((Double(hundredths) * Self.poundsPerKilogram / 10).rounded())
    }

    /// `286.6 lb`, or `397 lb` when the tenth is zero.
    var poundsLabel: String {
        let tenths = poundsTenths
        return tenths.isMultiple(of: 10) ? "\(tenths / 10) lb" : "\(tenths / 10).\(tenths % 10) lb"
    }

    private static let poundsPerKilogram = 2.20462262
}

extension Kilograms: Codable {
    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(Double.self)
        self.init(hundredths: Int((value * 100).rounded()))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Double(hundredths) / 100)
    }
}
