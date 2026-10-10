import CoreGraphics
import Testing

@testable import WorkoutTracker

private let iPhone17ProScreen = CGRect(x: 0, y: 0, width: 402, height: 874)

@Test func keyboardHideLeavesScreenWhenTheSoftwareKeyboardEndsBelowIt() {
    let endFrame = CGRect(x: 0, y: 874, width: 402, height: 336)

    #expect(KeyboardHide.leavesScreen(endFrame: endFrame, screenBounds: iPhone17ProScreen))
}

@Test func keyboardHideStaysOnScreenForTheHardwareKeyboardsMinimizedBar() {
    let endFrame = CGRect(x: 0, y: 792, width: 402, height: 82)

    #expect(!KeyboardHide.leavesScreen(endFrame: endFrame, screenBounds: iPhone17ProScreen))
}

@Test func keyboardHideStaysOnScreenWhilePartOfItRemainsVisible() {
    let endFrame = CGRect(x: 0, y: 873, width: 402, height: 336)

    #expect(!KeyboardHide.leavesScreen(endFrame: endFrame, screenBounds: iPhone17ProScreen))
}
