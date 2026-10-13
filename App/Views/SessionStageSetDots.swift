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
            // System secondary until #845 gives these dots a palette role that holds 3:1. On the Night
            // paper, with Color.secondary resolved as on macOS, the worst cases are 2.00:1 for the
            // skipped fill and 2.48:1 for the pending ring; the quiet futureStroke role would drop the
            // ring to 1.57:1.
            switch set.state {
            case .logged:
                Circle().fill(palette.accent)
            case .skipped:
                // swiftlint:disable:next system_ink_outside_the_palette
                Circle().fill(Color.secondary.opacity(0.45))
            case .pending:
                // swiftlint:disable:next system_ink_outside_the_palette
                Circle().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)
            }
        }
        .frame(width: dotSize, height: dotSize)
    }
}
