import Foundation

enum SetState: String, Codable, Sendable {
    case pending, logged, skipped
}

enum Weight: Codable, Sendable, Equatable {
    case bodyweight
    case pounds(Double)

    var label: String {
        switch self {
        case .bodyweight: return "BW"
        case .pounds(let v):
            return v.rounded() == v ? String(Int(v)) : String(v)
        }
    }
}

struct SetLog: Codable, Sendable, Equatable {
    var weight: Weight
    var reps: Int
    var rpe: Double

    init(weight: Weight, reps: Int, rpe: Double) {
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
    }

    init?(formatted raw: String) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let rpeParts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard
            rpeParts.count == 2,
            let rpe = Double(rpeParts[1].trimmingCharacters(in: .whitespaces)),
            rpe.isFinite
        else {
            return nil
        }

        let setParts = rpeParts[0].split(separator: "x", omittingEmptySubsequences: false)
        guard setParts.count == 2, let reps = Int(setParts[1].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }

        let weightText = setParts[0].trimmingCharacters(in: .whitespaces)
        let weight: Weight
        if weightText.caseInsensitiveCompare("BW") == .orderedSame {
            weight = .bodyweight
        } else if let pounds = Double(weightText), pounds.isFinite {
            weight = .pounds(pounds)
        } else {
            return nil
        }

        self.init(weight: weight, reps: reps, rpe: rpe)
    }

    var formatted: String {
        let rpeLabel = rpe.rounded() == rpe ? String(Int(rpe)) : String(rpe)
        return "\(weight.label)x\(reps)@\(rpeLabel)"
    }
}
