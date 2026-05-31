import SwiftUI

struct ExerciseSummaryRow: View {
    let exercise: Exercise
    let onTap: () -> Void
    @Environment(\.themePalette) private var palette

    private var presentation: ExerciseSummaryRowPresentation {
        ExerciseSummaryRowPresentation(exercise: exercise)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Text(presentation.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(palette.accent)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(presentation.title)
    }
}
