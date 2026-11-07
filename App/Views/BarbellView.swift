import SwiftUI

/// A bar seen from the side with the current load on it. One sleeve is drawn and the other is its
/// mirror. Plates keep their sizes, so a heavier load reads heavier before any number does.
struct BarbellView: View {
    let perSide: [PlateDenomination]
    @Environment(\.themePalette) private var palette

    static let loadAnimation = Animation.snappy(duration: 0.3)
    fileprivate static let height: CGFloat = 132
    private static let shaftLength: CGFloat = 66

    var body: some View {
        GeometryReader { proxy in
            let sideLength = (proxy.size.width - Self.shaftLength) / 2
            HStack(spacing: 0) {
                BarbellSide(perSide: perSide, length: sideLength)
                    .scaleEffect(x: -1)
                Rectangle()
                    .fill(palette.textSecondary)
                    .frame(width: Self.shaftLength, height: 6)
                BarbellSide(perSide: perSide, length: sideLength)
            }
            .frame(height: Self.height)
        }
        .frame(height: Self.height)
    }
}

private struct BarbellSide: View {
    let perSide: [PlateDenomination]
    let length: CGFloat
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let collarLength: CGFloat = 10

    private var layout: BarbellLayout {
        BarbellLayout(perSide: perSide, sleeveLength: length - Self.collarLength)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(palette.textSecondary.opacity(0.55))
                .frame(width: length, height: 12)

            RoundedRectangle(cornerRadius: 2.5)
                .fill(palette.textSecondary)
                .frame(width: Self.collarLength, height: 24)

            ForEach(layout.plates) { plate in
                plateView(plate)
                    .offset(x: Self.collarLength + plate.offset)
                    .transition(plateTransition)
            }
        }
        // One size whatever it holds, because the mirror's anchor follows this frame through a move.
        .frame(width: length, height: BarbellView.height, alignment: .leading)
        .animation(reduceMotion ? nil : BarbellView.loadAnimation, value: perSide)
    }

    private func plateView(_ plate: BarbellLayout.Plate) -> some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(palette.leafFill)
            .overlay {
                Capsule()
                    .fill(palette.leafRib)
                    .frame(width: min(1.5, plate.thickness / 5))
                    .padding(.vertical, 6)
            }
            .frame(width: plate.thickness, height: BarbellView.height * plate.height)
    }

    private var plateTransition: AnyTransition {
        reduceMotion ? .identity : .offset(x: 28).combined(with: .opacity)
    }
}

struct BarbellGlyph: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 24
            func bar(_ x: CGFloat, _ height: CGFloat, width: CGFloat) -> Path {
                let rect = CGRect(
                    x: x * scale,
                    y: (12 - height / 2) * scale,
                    width: width * scale,
                    height: height * scale
                )
                return Path(roundedRect: rect, cornerRadius: 1 * scale)
            }
            context.fill(bar(1, 2, width: 22), with: .color(color))
            context.fill(bar(4.5, 16, width: 3), with: .color(color))
            context.fill(bar(8.5, 10, width: 2), with: .color(color))
            context.fill(bar(13.5, 10, width: 2), with: .color(color))
            context.fill(bar(16.5, 16, width: 3), with: .color(color))
        }
    }
}
