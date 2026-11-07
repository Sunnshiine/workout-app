import SwiftUI

// MARK: - Weight ± stepper

/// A ~54pt round stepper flanking the weight value. Its triangle is sized by frame, not font, so
/// the control carries no inline font (type roles sheet, the choke point).
struct WeightStepperButton: View {
    enum Direction: Equatable { case decrement, increment }

    let direction: Direction
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let action: () -> Void
    @Environment(\.themePalette) private var palette

    private var glyph: String {
        direction == .decrement ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill"
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: glyph)
                .resizable()
                .scaledToFit()
                .foregroundStyle(palette.stepperGlyph)
                .frame(width: 16, height: 16)
                // A triangle's weight sits toward its base, so it is nudged toward its point to look centered.
                .offset(y: direction == .decrement ? 1.5 : -1.5)
                .frame(width: Theme.weightStepperDiameter, height: Theme.weightStepperDiameter)
                .background(palette.pillFill, in: .circle)
                .themeElevation(palette.lighting.raisedControlShadow, in: Circle())
        }
        .buttonStyle(.pressScale)
        .accessibilityShowsLargeContentViewer {
            Label(accessibilityLabel, systemImage: glyph)
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
