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

    var body: some View {
        Button(action: action) {
            Image(systemName: direction == .decrement ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(palette.stepperGlyph)
                .frame(width: 16, height: 16)
                .frame(width: Theme.weightStepperDiameter, height: Theme.weightStepperDiameter)
                .background(palette.pillFill, in: .circle)
                .overlay(Circle().strokeBorder(palette.pillStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(direction == .decrement ? "Decrease weight" : "Increase weight")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
