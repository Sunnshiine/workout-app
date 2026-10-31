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
                Circle().fill(palette.action)
            case .skipped:
                Circle().fill(palette.skipStroke)
            case .pending:
                Circle().strokeBorder(palette.textSecondary, lineWidth: 1)
            }
        }
        .frame(width: dotSize, height: dotSize)
    }
}
