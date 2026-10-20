import Foundation
import Testing

@testable import WorkoutTracker

/// Hosted only: the URL lives beside the Live Activity's attributes, which the app and the widget
/// compile and `swift test` does not.
@Suite
struct LiveActivityDictateLinkTests {
    @Test func theLiveActivityMicAsksTheAppToListenForTheCurrentSet() {
        #expect(WorkoutActivityAttributes.dictateURL.flatMap(AppEntryRequest.init(url:)) == .dictateCurrentSet)
    }
}
