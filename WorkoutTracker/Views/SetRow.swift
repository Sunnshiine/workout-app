import SwiftUI

struct SetRow: View {
    let set: ExerciseSet
    var showsSavedConfirmation = false
    let onTap: () -> Void
    @Environment(\.themePalette) private var palette

    private var presentation: SetRowPresentation {
        SetRowPresentation(set: set)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                if presentation.showsCheckmark {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(palette.accent)
                }

                Text("Set \(set.index + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .leading)

                Text(presentation.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(presentation.tone == .accent ? palette.accent : .secondary)

                if showsSavedConfirmation {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.accent)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.rowFill, in: .rect(cornerRadius: Theme.rowCornerRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set \(set.index + 1), \(presentation.title)")
    }
}
