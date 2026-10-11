/// Done must be on the keyboard before the field takes focus. A mounted field focused in the same
/// update that adds Done raised its keyboard without it, and the card landed at y124. So Done shows
/// only while editing, and focus is a request the View honours one update later.
struct WeightFieldMount {
    /// `folding` keeps the field mounted until its keyboard has hidden. Unmounting the field while
    /// its keyboard hides drops the stage's keyboard animation, and the card jumps.
    private enum Phase { case idle, editing, folding }

    private var phase = Phase.idle
    /// Bumped on every tap, so each tap asks for focus again, in the update after Done is installed.
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

    /// A re-tap during a fold receives the old hide's didHide either before or after its own focus
    /// commits, so a hide ends only a fold.
    mutating func keyboardDidHide() {
        if phase == .folding { phase = .idle }
    }

    var mountsField: Bool { phase != .idle }

    /// A Done left up through a hide drops out of later keyboards' bottom inset.
    var showsDone: Bool { phase == .editing }
}
