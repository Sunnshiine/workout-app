import SwiftUI

struct SetRow: View {
    let set: ExerciseSet
    let onTap: () -> Void

    private var presentation: SetRowPresentation {
        SetRowPresentation(set: set)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                if presentation.showsCheckmark {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                }

                Text("Set \(set.index + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .leading)

                Text(presentation.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(presentation.tone == .accent ? Theme.accent : .secondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set \(set.index + 1), \(presentation.title)")
    }
}
