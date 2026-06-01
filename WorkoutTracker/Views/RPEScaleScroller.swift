import SwiftUI

/// Fixed-height horizontal RPE chip scroller for the active set card. Nothing
/// here ever expands the card, so the Log button below keeps a fixed Y. One tap
/// selects any visible chip; the scroller starts centered on the prescribed or
/// selected value.
struct RPEScaleScroller: View {
    private enum Layout {
        static let edgeFadeWidth: CGFloat = 16
        static let trackVerticalPadding: CGFloat = 4
    }

    let presentation: RPEScalePresentation
    let onSelect: (String) -> Void
    @Environment(\.themePalette) private var palette
    @State private var didPositionInitialTarget = false

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Text("RPE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            ScrollViewReader { proxy in
                selectorTrack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.rpeScaleChipSpacing) {
                            ForEach(presentation.chips) { chip in
                                chipButton(chip)
                                    .id(chip.value)
                            }
                        }
                        .padding(.vertical, Layout.trackVerticalPadding)
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .task {
                        guard !didPositionInitialTarget else { return }
                        didPositionInitialTarget = true
                        await Task.yield()
                        // Centre once on mount (prescribed/selected value). Later taps move
                        // the selection in place — we deliberately do not re-scroll, so do
                        // not add `.id(scrollTarget)` here or every tap would jump the track.
                        proxy.scrollTo(presentation.scrollTarget, anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
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

    private func selectorTrack<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .frame(height: Theme.rpeScaleHeight)
            .background(palette.pillFill.opacity(0.72), in: .rect(cornerRadius: Theme.pillCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                    .strokeBorder(palette.pillStroke.opacity(0.7), lineWidth: 1)
            )
            .clipShape(.rect(cornerRadius: Theme.pillCornerRadius))
            .overlay(alignment: .leading) {
                edgeFade(startsOpaque: true)
            }
            .overlay(alignment: .trailing) {
                edgeFade(startsOpaque: false)
            }
    }

    private func edgeFade(startsOpaque: Bool) -> some View {
        LinearGradient(
            colors: startsOpaque ? [palette.pillFill, palette.pillFill.opacity(0)] : [palette.pillFill.opacity(0), palette.pillFill],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: Layout.edgeFadeWidth)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
