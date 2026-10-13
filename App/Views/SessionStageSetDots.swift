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
            // System secondary until a palette role holds 3:1 for these dots. On the Night paper the
            // pending ring's worst case is 2.48:1; the quiet futureStroke role would drop it to 1.57:1.
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
