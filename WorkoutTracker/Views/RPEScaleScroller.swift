import SwiftUI

/// Fixed-height horizontal RPE chip scroller for the active set card. Nothing
/// here ever expands the card, so the Log button below keeps a fixed Y. One tap
/// selects any visible chip; the scroller starts centered on the prescribed or
/// selected value.
struct RPEScaleScroller: View {
    let presentation: RPEScalePresentation
    let onSelect: (String) -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RPE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollViewReader { proxy in
                GeometryReader { geometry in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.rpeScaleChipSpacing) {
                            ForEach(presentation.chips) { chip in
                                chipButton(chip)
                                    .id(chip.value)
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, chipInset(forTrackWidth: geometry.size.width))
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .onAppear {
                        // Centre once on mount (prescribed/selected value). Later taps move
                        // the selection in place — we deliberately do not re-scroll, so do
                        // not add `.id(scrollTarget)` here or every tap would jump the track.
                        proxy.scrollTo(presentation.scrollTarget, anchor: .center)
                    }
                }
                .frame(height: Theme.rpeScaleHeight)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("RPE")
    }

    private func chipButton(_ chip: RPEChip) -> some View {
        Button {
            onSelect(chip.label)
        } label: {
            Text(chip.label)
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(chip.isDimmed ? Color.secondary : palette.valueText)
                .frame(width: Theme.rpeScaleChipWidth, height: Theme.rpeScaleHeight - 8)
                .background {
                    if chip.isSelected {
                        RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                            .fill(palette.pillFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                                    .strokeBorder(palette.accent, lineWidth: 2)
                            )
                    }
                }
                .overlay(alignment: .bottom) {
                    if chip.isPrescribed {
                        Capsule()
                            .fill(palette.accent)
                            .frame(width: 18, height: 3)
                            .accessibilityHidden(true)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("RPE \(chip.label)")
        .accessibilityIdentifier(chip.accessibilityIdentifier)
        .accessibilityAddTraits(chip.isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Half the track minus half a chip, so the first and last chips can scroll all
    /// the way to the centre regardless of screen width.
    private func chipInset(forTrackWidth width: CGFloat) -> CGFloat {
        max(Theme.rpeScaleChipWidth, (width - Theme.rpeScaleChipWidth) / 2)
    }
}
