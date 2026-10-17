extension Session {
    /// The Session as the Live Activity names it.
    var liveActivityLabel: String {
        if let address {
            return "Week \(address.week) - Day \(address.day)"
        }
        return "Day \(dayNumber)"
    }
}
