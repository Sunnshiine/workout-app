/// Keeps the weight's text field mounted from the tap that focuses it until the keyboard it raised
/// has gone. Unmounting the field while its keyboard hides drops the stage's keyboard animation, and
/// the card jumps.
struct WeightFieldMount: Equatable {
    private var holdsKeyboard = false

    mutating func fieldTakesFocus() {
        holdsKeyboard = true
    }

    /// A re-tap during a fold receives the old hide's didHide either before or after its own focus
    /// commits, so a hide releases only an unfocused field, and the focus that follows re-holds it.
    mutating func keyboardDidHide(fieldFocused: Bool) {
        holdsKeyboard = fieldFocused
    }

    func mountsField(focused: Bool) -> Bool {
        focused || holdsKeyboard
    }
}
