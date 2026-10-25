import Testing

@testable import WorkoutTracker

/// On screen the card listens whether or not a mic exists, since the stage shows the request
/// ending where it is; behind, only a mic can listen.
@Test(arguments: [
    (inBackground: false, hasMic: true, route: LogSetByVoiceRoute.card),
    (inBackground: false, hasMic: false, route: .card),
    (inBackground: true, hasMic: true, route: .headless),
    (inBackground: true, hasMic: false, route: .nothing)
])
func aLogASetRequestGoesToTheCardOnScreenAndListensHeadlessOnlyBehindWithAMic(
    inBackground: Bool,
    hasMic: Bool,
    route: LogSetByVoiceRoute
) {
    #expect(LogSetByVoiceRoute.route(appIsInBackground: inBackground, hasMic: hasMic) == route)
}
