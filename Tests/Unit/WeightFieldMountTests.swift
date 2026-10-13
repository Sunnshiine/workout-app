import Testing

@testable import WorkoutTracker

@Test func tapMountsTheFieldWithDoneAndRequestsFocusThenTheHideUnmountsIt() {
    var mount = WeightFieldMount()
    #expect(mount.mountsField == false)
    #expect(mount.showsDone == false)
    #expect(mount.focusRequests == 0)

    mount.tapped()
    #expect(mount.mountsField == true)
    #expect(mount.showsDone == true)
    #expect(mount.focusRequests == 1)

    mount.focusChanged(to: true)
    mount.focusChanged(to: false)
    #expect(mount.mountsField == true)
    #expect(mount.showsDone == false)

    mount.keyboardDidHide()
    #expect(mount.mountsField == false)
    #expect(mount.showsDone == false)
}

@Test func reTapWhoseFocusCommitsBeforeTheOldHideKeepsEditing() {
    var mount = WeightFieldMount()
    mount.tapped()
    mount.focusChanged(to: true)
    mount.focusChanged(to: false)

    mount.tapped()
    mount.focusChanged(to: true)
    mount.keyboardDidHide()
    #expect(mount.mountsField == true)
    #expect(mount.showsDone == true)

    mount.focusChanged(to: false)
    mount.keyboardDidHide()
    #expect(mount.mountsField == false)
    #expect(mount.showsDone == false)
}

@Test func reTapWhoseOldHideArrivesBeforeItsFocusKeepsTheFieldAndDone() {
    var mount = WeightFieldMount()
    mount.tapped()
    mount.focusChanged(to: true)
    mount.focusChanged(to: false)

    mount.tapped()
    mount.keyboardDidHide()
    #expect(mount.mountsField == true)
    #expect(mount.showsDone == true)

    mount.focusChanged(to: true)
    mount.focusChanged(to: false)
    mount.keyboardDidHide()
    #expect(mount.mountsField == false)
    #expect(mount.showsDone == false)
}

@Test func everyTapRequestsFocusAgainEvenWhenTheLastRequestNeverLanded() {
    var mount = WeightFieldMount()
    mount.tapped()
    mount.tapped()

    #expect(mount.focusRequests == 2)
    #expect(mount.mountsField == true)
    #expect(mount.showsDone == true)
}

@Test func focusWithoutATapMountsTheFieldAndShowsDone() {
    var mount = WeightFieldMount()
    mount.focusChanged(to: true)

    #expect(mount.mountsField == true)
    #expect(mount.showsDone == true)
    #expect(mount.focusRequests == 0)
}

@Test func aHideWhileTheFieldStillHasFocusKeepsTheFieldAndDone() {
    var mount = WeightFieldMount()
    mount.tapped()
    mount.focusChanged(to: true)
    mount.keyboardDidHide()

    #expect(mount.mountsField == true)
    #expect(mount.showsDone == true)
}
