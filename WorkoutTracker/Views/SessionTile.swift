import SwiftUI

/// A wordless Block-grid day tile: fill and stroke alone say state — inked complete,
/// cream-bud current with the sunlit-hour glow, quiet available (with ink rising from the
/// foot in quantized quarters for partial work), and the dashed empty bed for an
/// un-uploaded day. No text, no icons — the lock is dead (DESIGN.md §5.5).
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
                // Ink rising from the foot in quantized quarters — partial work made visible.
                palette.leafFill.opacity(0.85)
                    .frame(maxWidth: .infinity)
                    .frame(height: height * CGFloat(fillQuarters) / 4)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(shape)
        .overlay { strokeOverlay }
        .shadow(color: glowColor, radius: glowRadius)
    }

    @ViewBuilder
    private var baseFill: some View {
        switch state {
        case .complete:
            palette.leafFill
        case .current:
            palette.tileCurrentFill
        case .incomplete:
            palette.footFill
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

    /// The current tile alone carries a glow — the page's one delight — lit by the approved
    /// rim by Day and the bud glow at Night.
    private var glowColor: Color {
        state == .current ? (palette.budGlow ?? palette.tileCurrentBorder.opacity(0.35)) : .clear
    }

    private var glowRadius: CGFloat {
        state == .current && variant == .full ? Theme.blockFocusGlowRadius / 2 : 0
    }
}
