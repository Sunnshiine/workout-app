import SwiftUI

/// One dot per Set: filled accent when logged, dimmed when skipped, hollow when
/// pending. Tappable dots focus their Set and read as the Set Log (matching the
/// Set Row vocabulary); a ring marks the Set currently on stage.
struct SessionStageSetDots: View {
    let sets: [ExerciseSet]
    var currentSetID: ActiveSetID?
    var dotSize: CGFloat = 6
    var onTap: ((ExerciseSet) -> Void)?
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: dotSize) {
            ForEach(sets, id: \.persistentModelID) { set in
                if let onTap {
                    Button {
                        onTap(set)
                    } label: {
                        dot(for: set)
                            .padding(dotSize / 2)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Set \(set.index + 1), \(SetRowPresentation(set: set).title)")
                } else {
                    dot(for: set)
                }
            }
        }
        .accessibilityElement(children: onTap == nil ? .ignore : .contain)
    }

    @ViewBuilder
    private func dot(for set: ExerciseSet) -> some View {
        let isCurrent = currentSetID != nil && SessionCoordinator.activeSetID(for: set) == currentSetID
        Group {
            switch set.state {
            case .logged:
                Circle().fill(palette.accent)
            case .skipped:
                Circle().fill(Color.secondary.opacity(0.45))
            case .pending:
                Circle().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
            }
        }
        .frame(width: dotSize, height: dotSize)
        .overlay {
            if isCurrent {
                Circle()
                    .strokeBorder(palette.accent, lineWidth: 1.5)
                    .padding(-(dotSize / 2))
            }
        }
    }
}
