import Testing

@testable import WorkoutTracker

@Test func tappedWeightFieldMountsBeforeFocusAndStaysUntilItsKeyboardHasGone() {
    var mount = WeightFieldMount()
    #expect(mount.mountsField(focused: false) == false)

    mount.tapped()
    #expect(mount.mountsField(focused: false) == true)
    mount.focusChanged(to: true)
    mount.focusChanged(to: false)
    #expect(mount.mountsField(focused: false) == true)

    mount.keyboardDidHide(fieldFocused: false)
    #expect(mount.mountsField(focused: false) == false)
}

@Test func reTapWhoseFocusCommitsBeforeTheOldHideKeepsTheNextFoldMounted() {
    var mount = WeightFieldMount()
    mount.tapped()
    mount.focusChanged(to: true)
    mount.focusChanged(to: false)

    mount.tapped()
    mount.focusChanged(to: true)
    mount.keyboardDidHide(fieldFocused: true)
    mount.focusChanged(to: false)

    #expect(mount.mountsField(focused: false) == true)
    mount.keyboardDidHide(fieldFocused: false)
    #expect(mount.mountsField(focused: false) == false)
}

@Test func reTapWhoseFocusCommitsAfterTheOldHideKeepsTheNextFoldMounted() {
    var mount = WeightFieldMount()
    mount.tapped()
    mount.focusChanged(to: true)
    mount.focusChanged(to: false)

    mount.tapped()
    mount.keyboardDidHide(fieldFocused: false)
    mount.focusChanged(to: true)
    mount.focusChanged(to: false)

    #expect(mount.mountsField(focused: false) == true)
    mount.keyboardDidHide(fieldFocused: false)
    #expect(mount.mountsField(focused: false) == false)
}

@Test func doneShowsFromTheTapUntilFocusLeavesEvenWhileTheFieldStaysMounted() {
    var mount = WeightFieldMount()
    #expect(mount.showsDone == false)

    mount.tapped()
    #expect(mount.showsDone == true)
    mount.focusChanged(to: true)
    mount.focusChanged(to: false)
    #expect(mount.showsDone == false)
    #expect(mount.mountsField(focused: false) == true)

    mount.tapped()
    #expect(mount.showsDone == true)
}
