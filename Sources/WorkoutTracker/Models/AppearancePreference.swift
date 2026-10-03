enum AppearancePreference: String, CaseIterable {
    case system
    case light
    case night = "dark"

    var label: String {
        switch self {
        case .system:
            "System"
        case .light:
            "Light"
        case .night:
            "Night"
        }
    }
}
