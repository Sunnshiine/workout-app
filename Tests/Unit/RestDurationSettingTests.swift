import Foundation
import Testing

@testable import WorkoutTracker

@Test func restDurationSettingDefaultsToStandardRest() {
    #expect(RestDurationSetting.standard.seconds == 120)
    #expect(RestDurationSetting.standard.timeInterval == 120)
    #expect(RestDurationSetting.standard.displayText == "2:00")
}

@Test func restDurationSettingClampsAtBounds() {
    #expect(RestDurationSetting(seconds: 1).seconds == 30)
    #expect(RestDurationSetting(seconds: 30).seconds == 30)
    #expect(RestDurationSetting(seconds: 600).seconds == 600)
    #expect(RestDurationSetting(seconds: 900).seconds == 600)
}

@Test func restDurationSettingStepsByThirtySecondsAndStopsAtFloorAndCeiling() {
    #expect(RestDurationSetting(seconds: 30).decremented().seconds == 30)
    #expect(RestDurationSetting(seconds: 30).incremented().seconds == 60)
    #expect(RestDurationSetting(seconds: 570).incremented().seconds == 600)
    #expect(RestDurationSetting(seconds: 600).incremented().seconds == 600)
    #expect(RestDurationSetting(seconds: 600).decremented().seconds == 570)
}
