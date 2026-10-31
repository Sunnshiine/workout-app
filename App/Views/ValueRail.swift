import SwiftUI

// MARK: - Value rail (Reps / RPE)

struct ValueRail: View {
    let chips: [ValueRailChip]
    let selectedIndex: Int
    let label: String
    var isInvalid = false
    let onSelect: (String) -> Void
    @State private var dragAnchorIndex: Int?
    /// A drag is in flight (or just ended this event turn). It gates the cell buttons: as the strip
    /// re-centers on the dragged value, the lifted finger sits over a *different* cell, and that
    /// cell's button firing on release would override the drag — snapping the value back to where the
    /// finger landed (the reported "release jumps back to the original number"). The flag clears one
    /// runloop turn after the drag ends, after the synchronous release has been suppressed.
    @State private var isDragging = false
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let offset = ValueRailLayout.contentOffset(
                    trackWidth: geo.size.width,
                    cellWidth: Theme.railCellWidth,
                    spacing: 0,
                    selectedIndex: selectedIndex
                )

                HStack(spacing: 0) {
                    ForEach(chips) { chip in
                        cell(chip)
                    }
                }
                .frame(height: geo.size.height)
                .offset(x: offset)
                .animation(.snappy(duration: 0.22), value: selectedIndex)
            }
            .frame(height: Theme.railTrackHeight)
            .mask { edgeFadeMask }
            .background(palette.railFill, in: .rect(cornerRadius: Theme.Radius.rail))
            .clipShape(.rect(cornerRadius: Theme.Radius.rail))
            .contentShape(.rect(cornerRadius: Theme.Radius.rail))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.rail)
                    .strokeBorder(isInvalid ? palette.danger : .clear, lineWidth: 2)
            }
            .simultaneousGesture(dragToSelect)

            Text(label)
                .themeFont(.fieldLabel)
                .foregroundStyle(palette.textSecondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    /// Sliding the rail follows the finger detent by detent: each cell-width of horizontal travel
    /// moves the selection one value from where the drag began, with the detent tick on each move.
    /// Simultaneous with the cell buttons so taps keep working unchanged.
    private var dragToSelect: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                isDragging = true
                let anchor = dragAnchorIndex ?? selectedIndex
                dragAnchorIndex = anchor
                let target = ValueRailLayout.draggedIndex(
                    anchorIndex: anchor,
                    translation: value.translation.width,
                    cellWidth: Theme.railCellWidth,
                    spacing: 0,
                    count: chips.count
                )
                guard target != selectedIndex, chips.indices.contains(target) else { return }
                onSelect(chips[target].label)
                HapticPlayer.shared.play(.input(Theme.Haptics.railDetentTick))
            }
            .onEnded { _ in
                dragAnchorIndex = nil
                // Clear on the next runloop turn so the release's cell-button tap — dispatched in
                // this same event turn — still sees `isDragging` and is suppressed.
                DispatchQueue.main.async { isDragging = false }
            }
    }

    private func cell(_ chip: ValueRailChip) -> some View {
        Button {
            // A tap that was actually the tail of a drag must not re-select the cell under the
            // lifted finger — the drag's selection is authoritative (see `isDragging`).
            guard !isDragging else { return }
            onSelect(chip.label)
            HapticPlayer.shared.play(.input(Theme.Haptics.railDetentTick))
        } label: {
            Text(chip.label)
                .themeFont(.railChipValue)
                .foregroundStyle(chip.isSelected ? palette.textPrimary : palette.textSecondary)
                .frame(width: Theme.railCellWidth, height: Theme.railCellHeight)
                .contentShape(.rect)
                .background {
                    if chip.isSelected {
                        RoundedRectangle(cornerRadius: Theme.Radius.cell)
                            .fill(palette.railSelectedFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.cell)
                                    .strokeBorder(palette.action, lineWidth: 2)
                            )
                            .padding(Theme.railCellInset)
                    }
                }
                .overlay(alignment: .bottom) {
                    if chip.isPrescribed {
                        Capsule()
                            .fill(palette.prescriptionTick)
                            .frame(width: Theme.prescriptionTickWidth, height: Theme.prescriptionTickHeight)
                            .padding(.bottom, Theme.railCellInset + 3)
                            .accessibilityHidden(true)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityShowsLargeContentViewer {
            Text("\(label) \(chip.label)")
        }
        .accessibilityIdentifier(chip.accessibilityIdentifier)
        .accessibilityLabel("\(label) \(chip.label)")
        .accessibilityAddTraits(chip.isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Fades the chips out at both ends without painting over the rail's rounded fill.
    private var edgeFadeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: Theme.railEdgeFadeWidth)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: Theme.railEdgeFadeWidth)
        }
    }
}
