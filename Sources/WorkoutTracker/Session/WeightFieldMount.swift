/// Unmounting the field while its keyboard hides drops the stage's keyboard animation, and the card jumps.
struct WeightFieldMount {
    private var keepsField = false

    mutating func tapped() {
        keepsField = true
    }

    mutating func focusChanged(to focused: Bool) {
        if focused { keepsField = true }
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
