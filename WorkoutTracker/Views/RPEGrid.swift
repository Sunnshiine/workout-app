import SwiftUI

struct RPEGrid: View {
    private enum Layout {
        static let halfStepSelectorHeight: CGFloat = 44
        static let horizontalPadding: CGFloat = 4
        static let rowSpacing: CGFloat = 2
        static let separatorHeight: CGFloat = 1

        static var wholeStepHeight: CGFloat {
            Theme.rpeGridCellHeight - 4
        }

        static var totalHeight: CGFloat {
            wholeStepHeight + separatorHeight + rowSpacing * 2 + halfStepSelectorHeight
        }
    }

    let presentation: RPEGridPresentation
    @Binding var selection: String
    @Binding var isPresented: Bool

    var body: some View {
        scaleContent
            .frame(height: Layout.totalHeight)
    }

    private var scaleContent: some View {
        VStack(spacing: Layout.rowSpacing) {
            HStack(spacing: 0) {
                ForEach(values) { value in
                    wholeStepLabel(for: value)
                }
            }
            .frame(height: Layout.wholeStepHeight)
            .clipped()

            Rectangle()
                .fill(Theme.pillStroke.opacity(0.32))
                .frame(height: Layout.separatorHeight)

            HStack(spacing: 0) {
                ForEach(values) { value in
                    halfStepSlot(for: value)
                }
            }
            .frame(height: Layout.halfStepSelectorHeight)
            .clipped()
        }
        .padding(.horizontal, Layout.horizontalPadding)
    }

    @ViewBuilder
    private func halfStepSlot(for value: RPEGridValue) -> some View {
        if let halfStepLabel = value.halfStepLabel {
            Button {
                select(halfStepLabel)
            } label: {
                halfStepLabelView(label: halfStepLabel)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .accessibilityLabel("RPE \(halfStepLabel)")
            .accessibilityIdentifier("rpe-\(value.value)-half")
        } else {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: Layout.halfStepSelectorHeight)
                .accessibilityHidden(true)
        }
    }

    private func wholeStepLabel(for value: RPEGridValue) -> some View {
        Button {
            select(String(value.value))
        } label: {
            ZStack {
                Color.clear

                Text(String(value.value))
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.wholeStepHeight)
                    .foregroundStyle(value.isDimmed ? Color.secondary : Color.white)

                if value.showsPrescriptionBadge {
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: 18, height: 3)
                        .offset(y: 14)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Layout.wholeStepHeight)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityLabel("RPE \(value.value)")
        .accessibilityIdentifier("rpe-\(value.value)")
        .opacity(value.isDimmed ? 0.55 : 1)
    }

    private func halfStepLabelView(label: String) -> some View {
        ZStack {
            Color.clear

            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Layout.halfStepSelectorHeight)
    }

    private func select(_ text: String) {
        selection = text
        Task {
            try? await Task.sleep(for: presentation.autoCloseDelay)
            isPresented = false
        }
    }

    private var values: [RPEGridValue] {
        presentation.rows.flatMap { $0 }
    }
}
