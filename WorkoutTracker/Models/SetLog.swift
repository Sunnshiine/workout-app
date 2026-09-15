import Foundation

enum SetState: String, Codable, Sendable {
    case pending, logged, skipped
}

enum Weight: Codable, Sendable, Equatable {
    case bodyweight
    case pounds(Double)

    /// Reads the weight token every entry surface accepts: "BW" in any casing, or a finite
    /// number of pounds. The token must already be trimmed; callers own their own whitespace
    /// rules because they slice it out of differently shaped input.
    init?(text: String) {
        if text.caseInsensitiveCompare("BW") == .orderedSame {
            self = .bodyweight
            return
        }
        guard let pounds = Double(text), pounds.isFinite else {
            return nil
        }
        self = .pounds(pounds)
    }

    var label: String {
        switch self {
        case .bodyweight: return "BW"
        case .pounds(let v):
            return v.rounded() == v ? String(Int(v)) : String(v)
        }
    }
}

/// An RPE as the Sheet records or prescribes it: any finite point, printed `6` or `6.5`. Which points
/// the athlete may pick is the RPE rail's decision (`RPEScalePresentation.scale`), not this type's.
struct RPE: Hashable, Sendable, Codable, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
    private let point: Double

    init(integerLiteral value: Int) {
        point = Double(value)
    }

    init(floatLiteral value: Double) {
        point = value
    }

    /// The token must already be trimmed, the same convention as `Weight(text:)`.
    init?(text: String) {
        guard let point = Double(text), point.isFinite else {
            return nil
        }
        self.point = point
    }

    /// Reads the RPE out of a Prescribed Load such as `RPE6` or `rpe 8`.
    init?(prescribedLoad: String) {
        let trimmed = prescribedLoad.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.wholeMatch(of: /RPE\s*(.+)/.ignoresCase()) else {
            return nil
        }
        self.init(text: String(match.1))
    }

    init(from decoder: Decoder) throws {
        point = try Double(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try point.encode(to: encoder)
    }

    var label: String {
        Int(exactly: point).map(String.init) ?? String(point)
    }
}

struct SetLog: Codable, Sendable, Equatable {
    var weight: Weight
    var reps: Int
    var rpe: RPE

    init(weight: Weight, reps: Int, rpe: RPE) {
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
    }

    /// Splits `<weight>x<reps>@<rpe>` into its three trimmed, still unparsed tokens. Splitting on
    /// `@` first is what makes the order strict, so `185@5x8` is not the same Set Log as `185x5@8`.
    private static func tokens(inFormatted raw: String) -> FormattedSetLogTokens? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let rpeParts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard rpeParts.count == 2 else { return nil }

        let setParts = rpeParts[0].split(separator: "x", omittingEmptySubsequences: false)
        guard setParts.count == 2 else { return nil }

        return FormattedSetLogTokens(
            weight: setParts[0].trimmingCharacters(in: .whitespaces),
            reps: setParts[1].trimmingCharacters(in: .whitespaces),
            rpe: rpeParts[1].trimmingCharacters(in: .whitespaces)
        )
    }

    init?(formatted raw: String) {
        guard
            let tokens = Self.tokens(inFormatted: raw),
            let weight = Weight(text: tokens.weight),
            let reps = Int(tokens.reps),
            let rpe = RPE(text: tokens.rpe)
        else {
            return nil
        }

        self.init(weight: weight, reps: reps, rpe: rpe)
    }

    var formatted: String {
        "\(weight.label)x\(reps)@\(rpe.label)"
    }
}

/// The three still-unparsed tokens of `<weight>x<reps>@<rpe>`.
private struct FormattedSetLogTokens {
    let weight: String
    let reps: String
    let rpe: String
}
