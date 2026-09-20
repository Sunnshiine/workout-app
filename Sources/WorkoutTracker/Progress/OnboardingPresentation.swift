enum AppEntryDestination: Equatable {
    case signIn
    case sheetPicker
    case urlEntry
    case session

    init(isSignedIn: Bool, hasSpreadsheet: Bool, showsURLFallback: Bool) {
        if isSignedIn, hasSpreadsheet {
            self = .session
        } else if isSignedIn, showsURLFallback {
            self = .urlEntry
        } else if isSignedIn {
            self = .sheetPicker
        } else {
            self = .signIn
        }
    }
}
