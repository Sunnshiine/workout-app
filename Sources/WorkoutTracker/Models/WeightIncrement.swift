/// The step the inline weight stepper takes. Plates come in pairs, so the useful step is a fixed
/// size rather than a fraction of the load. It is 2.5 at or below the gym-friendly threshold and 5
/// above it, and a weight the field cannot parse yet steps by the smaller one.
enum WeightIncrement {
    static let threshold = 100.0

    static func fine(forWeight weight: Double?) -> Double {
        guard let weight, weight > threshold else { return 2.5 }
        return 5
    }
}
