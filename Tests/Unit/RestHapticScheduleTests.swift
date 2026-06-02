import Testing

@testable import WorkoutTracker

@Test func restHapticScheduleFiresFinalFiveTapsAndExpiryBuzz() {
    let events = RestHapticSchedule(duration: 120).events

    #expect(
        events == [
            RestHapticEvent(offset: 115, kind: .lightTap),
            RestHapticEvent(offset: 116, kind: .lightTap),
            RestHapticEvent(offset: 117, kind: .lightTap),
            RestHapticEvent(offset: 118, kind: .lightTap),
            RestHapticEvent(offset: 119, kind: .lightTap),
            RestHapticEvent(offset: 120, kind: .expiryBuzz)
        ]
    )
}

@Test func restHapticScheduleKeepsFinalFiveRampForShortDuration() {
    let events = RestHapticSchedule(duration: 30).events

    #expect(
        events == [
            RestHapticEvent(offset: 25, kind: .lightTap),
            RestHapticEvent(offset: 26, kind: .lightTap),
            RestHapticEvent(offset: 27, kind: .lightTap),
            RestHapticEvent(offset: 28, kind: .lightTap),
            RestHapticEvent(offset: 29, kind: .lightTap),
            RestHapticEvent(offset: 30, kind: .expiryBuzz)
        ]
    )
}
