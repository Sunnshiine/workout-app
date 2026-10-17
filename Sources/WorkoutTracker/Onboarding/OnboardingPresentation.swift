enum OnboardingStep: Equatable {
    case signIn
    case sheetPicker
    case urlEntry

    init(isSignedIn: Bool, showsURLFallback: Bool) {
        if !isSignedIn {
            self = .signIn
        } else if showsURLFallback {
            self = .urlEntry
        } else {
            self = .sheetPicker
        }
    }
}
