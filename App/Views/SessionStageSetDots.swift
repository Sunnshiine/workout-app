import SwiftUI

struct SessionStageSetDots: View {
    let sets: [ExerciseSet]
    private let dotSize: CGFloat = 6
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: dotSize) {
            ForEach(sets, id: \.persistentModelID) { set in
                dot(for: set)
            }
        }
        .accessibilityElement(children: .ignore)
    }

    @ViewBuilder
    private func dot(for set: ExerciseSet) -> some View {
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
    }
}
