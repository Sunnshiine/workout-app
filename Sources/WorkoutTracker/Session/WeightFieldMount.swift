/// Done must be on the keyboard before the field takes focus. A mounted field focused in the same
/// update that adds Done raised its keyboard without it. So Done shows only while editing, and focus
/// is a request the View honours one update later.
struct WeightFieldMount {
    /// Unmounting the field while its keyboard hides drops the stage's keyboard animation, and the
    /// card jumps.
    private enum Phase { case idle, editing, folding }

    private var phase = Phase.idle
    private(set) var focusRequests = 0

    mutating func tapped() {
        phase = .editing
        focusRequests += 1
    }

    mutating func focusChanged(to focused: Bool) {
        if focused {
            phase = .editing
        } else if phase == .editing {
            phase = .folding
        }
    }

    mutating func keyboardDidHide() {
        if phase == .folding { phase = .idle }
    }

    var mountsField: Bool { phase != .idle }

    /// A Done left up through a hide drops out of later keyboards' bottom inset.
    var showsDone: Bool { phase == .editing }
}
