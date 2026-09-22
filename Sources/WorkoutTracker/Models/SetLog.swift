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
            return Int(exactly: v).map(String.init) ?? String(v)
        }
    }
}

enum RPE: Double, CaseIterable, Codable, Hashable, Sendable {
    case five = 5
    case six = 6
    case sixPointFive = 6.5
    case seven = 7
    case sevenPointFive = 7.5
    case eight = 8
    case eightPointFive = 8.5
    case nine = 9
    case ninePointFive = 9.5
    case ten = 10

    init?(text: String) {
        guard let point = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        self.init(rawValue: point)
    }

    init?(prescribedLoad: String) {
        let trimmed = prescribedLoad.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.wholeMatch(of: /RPE\s*(.+)/.ignoresCase()) else {
            return nil
        }
        self.init(text: String(match.1))
    }

    var label: String {
        Int(exactly: rawValue).map(String.init) ?? String(rawValue)
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
