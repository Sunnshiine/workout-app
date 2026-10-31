import SwiftUI

// MARK: - Weight ± stepper

/// A ~54pt round stepper flanking the weight value. Its triangle is sized by frame, not font, so
/// the control carries no inline font (token sheet §4 choke point).
struct WeightStepperButton: View {
    enum Direction: Equatable { case decrement, increment }

    let direction: Direction
    let accessibilityIdentifier: String
    let action: () -> Void
    @Environment(\.themePalette) private var palette
    @GestureState private var isPressed = false

    private static let bounds = CGRect(
        x: 0,
        y: 0,
        width: Theme.weightStepperDiameter,
        height: Theme.weightStepperDiameter
    )

    var body: some View {
        Button(action: action) {
            Image(systemName: direction == .decrement ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(palette.stepperGlyph)
                .frame(width: 16, height: 16)
                .frame(width: Theme.weightStepperDiameter, height: Theme.weightStepperDiameter)
                .background(palette.pillFill, in: .circle)
                .themeElevation(palette.lighting.raisedControlShadow, in: Circle())
        }
        .buttonStyle(.plain)
        // The plain style keeps its pressed and disabled dims; the Log capsule's press scale rides on top (§5.3).
        .scaleEffect(isPressed ? Theme.pressScale : 1)
        .animation(Theme.pressAnimation, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).updating($isPressed) { drag, pressing, _ in
                // The scale lets go once the finger leaves the stepper, a little before the dim does.
                pressing = Self.bounds.contains(drag.location)
            }
        )
        .accessibilityLabel(direction == .decrement ? "Decrease weight" : "Increase weight")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
