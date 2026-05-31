import SwiftUI

/// Stable A / B identity tag for the two Exercises in a Superset.
/// The active side uses the accent (mint means current); the resting side stays quiet.
struct SupersetIdentityBadge: View {
    let label: String
    let isActive: Bool
    @Environment(\.themePalette) private var palette

    var body: some View {
        Text(label)
            .font(.caption.weight(.bold))
            .foregroundStyle(isActive ? palette.accentDarkText : .secondary)
            .frame(width: 20, height: 20)
            .background(
                isActive ? palette.accent : palette.pillFill,
                in: .rect(cornerRadius: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isActive ? Color.clear : palette.pillStroke.opacity(0.6),
                        lineWidth: 1
                    )
            )
            .accessibilityHidden(true)
    }
}
