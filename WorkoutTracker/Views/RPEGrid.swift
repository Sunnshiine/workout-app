import SwiftUI

struct RPEGrid: View {
    private enum Layout {
        static let halfStepBubbleOffset: CGFloat = -34
        static let highlightedHalfStepScale = 1.08
        static let longPressDuration = 0.35
        static let bubbleAnimationDuration = 0.12
    }

    let presentation: RPEGridPresentation
    @Binding var selection: String
    @Binding var isPresented: Bool
    @State private var revealedHalfStepValue: Int?
    @State private var activeDragHeight = 0.0

    var body: some View {
        VStack(spacing: Theme.rpeGridSpacing) {
            ForEach(presentation.rows.indices, id: \.self) { rowIndex in
                rowView(presentation.rows[rowIndex])
            }
        }
    }

    private func rowView(_ row: [RPEGridValue]) -> some View {
        HStack(spacing: Theme.rpeGridSpacing) {
            ForEach(row) { value in
                cellControl(for: value)
            }
        }
    }

    @ViewBuilder
    private func cellControl(for value: RPEGridValue) -> some View {
        let control = ZStack(alignment: .top) {
            cellLabel(for: value)

            if revealedHalfStepValue == value.value, let halfStepLabel = value.halfStepLabel {
                Text(halfStepLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accentDarkText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.accent, in: .capsule)
                    .scaleEffect(
                        activeDragHeight <= -RPEGridValue.halfStepActivationOffset
                            ? Layout.highlightedHalfStepScale
                            : 1
                    )
                    .offset(y: Layout.halfStepBubbleOffset)
                    .accessibilityIdentifier("rpe-\(value.value)-half")
            }
        }
        .contentShape(Rectangle())
        .gesture(dragGesture(for: value))
        .simultaneousGesture(longPressGesture(for: value))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("RPE \(value.value)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            select(String(value.value))
        }
        .accessibilityIdentifier("rpe-\(value.value)")
        .zIndex(revealedHalfStepValue == value.value ? 1 : 0)

        if let halfStepLabel = value.halfStepLabel {
            control.accessibilityAction(named: Text("Select \(halfStepLabel)")) {
                select(halfStepLabel)
            }
        } else {
            control
        }
    }

    private func dragGesture(for value: RPEGridValue) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                guard revealedHalfStepValue == value.value else { return }
                activeDragHeight = drag.translation.height
            }
            .onEnded { drag in
                select(
                    value.selectionText(
                        halfStepWasRevealed: revealedHalfStepValue == value.value,
                        verticalDrag: drag.translation.height
                    )
                )
            }
    }

    private func longPressGesture(for value: RPEGridValue) -> some Gesture {
        LongPressGesture(minimumDuration: Layout.longPressDuration)
            .onEnded { _ in
                guard value.halfStepLabel != nil else { return }
                withAnimation(.easeOut(duration: Layout.bubbleAnimationDuration)) {
                    revealedHalfStepValue = value.value
                    activeDragHeight = 0
                }
            }
    }

    private func select(_ text: String) {
        selection = text
        revealedHalfStepValue = nil
        activeDragHeight = 0
        Task {
            try? await Task.sleep(for: presentation.autoCloseDelay)
            isPresented = false
        }
    }

    private func cellLabel(for value: RPEGridValue) -> some View {
        ZStack(alignment: .topTrailing) {
            Text(String(value.value))
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: Theme.rpeGridCellHeight)
                .foregroundStyle(value.isDimmed ? Color.secondary : Theme.valueText)

            if value.showsPrescriptionBadge {
                Text("Rx")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.accentDarkText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Theme.accent, in: .capsule)
                    .padding(6)
            }
        }
        .background(Theme.pillFill, in: .rect(cornerRadius: Theme.pillCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                .strokeBorder(Theme.pillStroke, lineWidth: 1)
        )
        .opacity(value.isDimmed ? 0.55 : 1)
    }
}
