/// Unmounting the field while its keyboard hides drops the stage's keyboard animation, and the card jumps.
struct WeightFieldMount {
    private var keepsField = false
    /// The keyboard's Done shows from the tap and leaves with focus. A field that takes focus in the
    /// same update that adds Done can raise its keyboard without it, and a Done left up through the
    /// keyboard's hide drops out of later keyboards' bottom inset; either way the card misses the keyboard.
    private(set) var showsDone = false

    mutating func tapped() {
        keepsField = true
        showsDone = true
    }

    mutating func focusChanged(to focused: Bool) {
        if focused { keepsField = true } else { showsDone = false }
    }

    /// A re-tap during a fold receives the old hide's didHide either before or after its own focus
    /// commits.
    mutating func keyboardDidHide(fieldFocused: Bool) {
        keepsField = fieldFocused
    }

    func mountsField(focused: Bool) -> Bool {
        focused || keepsField
    }
}
