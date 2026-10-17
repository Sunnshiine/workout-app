import Testing

@testable import WorkoutTracker

@Test func onboardingShowsSignInBeforeGoogleAuth() {
    #expect(OnboardingStep(isSignedIn: false, showsURLFallback: false) == .signIn)
    #expect(OnboardingStep(isSignedIn: false, showsURLFallback: true) == .signIn)
}

@Test func onboardingFlowsFromSheetPickerToURLFallbackAndBack() {
    #expect(OnboardingStep(isSignedIn: true, showsURLFallback: false) == .sheetPicker)
    #expect(OnboardingStep(isSignedIn: true, showsURLFallback: true) == .urlEntry)
}
