extension Session {
    /// The Session as the Live Activity names it.
    var liveActivityLabel: String {
        placement.locationText(separator: " - ")
    }
}
