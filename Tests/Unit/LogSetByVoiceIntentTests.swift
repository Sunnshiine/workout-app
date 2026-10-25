import AppIntents
import Testing

@testable import WorkoutTracker

/// Hosted only: the intent lives beside the Live Activity's attributes, which the app and the
/// widget compile and `swift test` does not.
@Suite
struct LogSetByVoiceIntentTests {
    /// Background mode is what lets the Action button and a control run it on a locked phone, and
    /// the default authentication policy is what lets it run without an unlock.
    @Test func logASetRunsInTheBackgroundWithoutAuthentication() {
        #expect(LogSetByVoiceIntent.supportedModes == .background)
        #expect(LogSetByVoiceIntent.authenticationPolicy == .alwaysAllowed)
    }
}
