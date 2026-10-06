import SwiftUI

struct SessionTile: View {
    enum Variant {
        /// A full day tile in the focus week.
        case full
        /// A mini chip in a collapsed week card's day-strip.
        case mini
    }

    let state: SessionTileState
    let fillQuarters: Int
    var variant: Variant = .full
    @Environment(\.themePalette) private var palette

    private var height: CGFloat {
        variant == .full ? Theme.blockTileHeight : Theme.blockTileMiniHeight
    }

    private var cornerRadius: CGFloat {
        variant == .full ? Theme.Radius.tile : Theme.Radius.mini
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            baseFill
            if state == .incomplete, fillQuarters > 0 {
                // Ink rising from the foot in quantized quarters — partial work made visible,
                // in the full complete pigment (`tileComplete`), never a faded tint.
                palette.leafFill
                    .frame(maxWidth: .infinity)
                    .frame(height: height * CGFloat(fillQuarters) / 4)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .overlay {
            if variant == .full, state != .unavailable, let topLight = palette.lighting.tileTopLight {
                topLight.gradientView
                    .allowsHitTesting(false)
            }
        }
        .clipShape(shape)
        .overlay { strokeOverlay }
        .themeElevation(
            state == .current && variant == .full ? palette.lighting.currentTileGlow : [],
            in: RoundedRectangle(cornerRadius: Theme.Radius.tile)
        )
    }

    @ViewBuilder
    private var baseFill: some View {
        switch state {
        case .complete:
            palette.leafFill
        case .current:
            palette.tileCurrentFill
        case .incomplete:
            // Quiet available — cream @ 85% (`pillFill`), the resting tile base.
            palette.pillFill
        case .unavailable:
            Color.clear
        }
    }

    @ViewBuilder
    private var strokeOverlay: some View {
        switch state {
        case .complete:
            EmptyView()
        case .current:
            shape.stroke(palette.tileCurrentBorder, lineWidth: Theme.blockTileCurrentStroke)
        case .incomplete:
            shape.stroke(palette.queueStroke, lineWidth: Theme.blockTileStroke)
        case .unavailable:
            shape.stroke(
                palette.tileGhostStroke,
                style: StrokeStyle(lineWidth: Theme.blockTileGhostStroke, dash: [Theme.blockTileGhostDash])
            )
        }
    }
}
