import Testing

@testable import WorkoutTracker

@Test func foldedWeightFieldStaysMountedUntilItsKeyboardHasGone() {
    var mount = WeightFieldMount()
    #expect(mount.mountsField(focused: false) == false)

    mount.fieldTakesFocus()
    #expect(mount.mountsField(focused: true) == true)
    #expect(mount.mountsField(focused: false) == true)

    mount.keyboardDidHide(fieldFocused: false)
    #expect(mount.mountsField(focused: false) == false)
}

@Test func reTapThatFocusesBeforeTheOldHideKeepsTheNextFoldMounted() {
    var mount = WeightFieldMount()
    mount.fieldTakesFocus()

    mount.fieldTakesFocus()
    mount.keyboardDidHide(fieldFocused: true)

    #expect(mount.mountsField(focused: false) == true)
    mount.keyboardDidHide(fieldFocused: false)
    #expect(mount.mountsField(focused: false) == false)
}
