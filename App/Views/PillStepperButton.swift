import SwiftUI

struct PillStepperButton: View {
    let systemName: String
    let accessibilityIdentifier: String
    var isEnabled = true
    let action: () -> Void

    @Environment(\.themePalette) private var palette

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(Theme.font(.railChipValue))
                .foregroundStyle(isEnabled ? palette.accent : .secondary)
                .frame(
                    width: WeightPillLayoutMetrics.stepperButtonSize,
                    height: WeightPillLayoutMetrics.stepperButtonSize
                )
                .background(palette.pillFill, in: .capsule)
                .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
