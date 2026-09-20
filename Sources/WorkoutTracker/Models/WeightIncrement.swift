/// Plates come in pairs, so a useful step is a fixed weight rather than a fraction of the load.
enum WeightIncrement {
    static let threshold = 100.0

    static func fine(forWeight weight: Double?) -> Double {
        guard let weight, weight > threshold else { return 2.5 }
        return 5
    }
}
