import Testing

@testable import WorkoutTracker

@Test func onboardingShowsSignInBeforeGoogleAuth() {
    let destination = AppEntryDestination(
        isSignedIn: false,
        hasSpreadsheet: false,
        showsURLFallback: false
    )

    #expect(destination == .signIn)
}

@Test func onboardingFlowsFromSheetPickerToURLFallbackAndBack() {
    let picker = AppEntryDestination(
        isSignedIn: true,
        hasSpreadsheet: false,
        showsURLFallback: false
    )
    let urlEntry = AppEntryDestination(
        isSignedIn: true,
        hasSpreadsheet: false,
        showsURLFallback: true
    )

    #expect(picker == .sheetPicker)
    #expect(urlEntry == .urlEntry)
}

@Test func onboardingSkipsPickerWhenSpreadsheetAlreadyConfigured() {
    let destination = AppEntryDestination(
        isSignedIn: true,
        hasSpreadsheet: true,
        showsURLFallback: false
    )
    let fallbackDestination = AppEntryDestination(
        isSignedIn: true,
        hasSpreadsheet: true,
        showsURLFallback: true
    )

    #expect(destination == .session)
    #expect(fallbackDestination == .session)
}
