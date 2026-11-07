import SwiftUI

/// The Lens's way to the ramp. It presents the sheet, so the sheet leaves when the entry does, and
/// it offers nothing while the Bar alone outweighs the Set.
struct WarmupRampButton: View {
    let entry: WarmupEntry
    let coordinator: SessionCoordinator
    let size: CGFloat
    @Environment(SettingsStore.self) private var settings
    @Environment(\.themePalette) private var palette
    @State private var isPresented = false

    var body: some View {
        if entry.hasWalk(on: settings.plateInventory) {
            Button {
                isPresented = true
            } label: {
                BarbellGlyph(color: palette.actionInk)
                    .frame(width: 24, height: 24)
                    .frame(width: size, height: size)
                    .background(Circle().fill(palette.pillFill))
                    .themeElevation(palette.lighting.raisedControlShadow, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Warm-up Ramp")
            .accessibilityIdentifier("stage-queue-warmup")
            .sheet(isPresented: $isPresented) {
                WarmupRampSheet(entry: entry, coordinator: coordinator)
            }
        }
    }
}

/// The walk up to a Set: a drawn bar with exactly what goes on each side, and the steps beneath it. A
/// tap marks a step for this Session alone. Nothing here reaches the card or the Sheet.
struct WarmupRampSheet: View {
    let entry: WarmupEntry
    let coordinator: SessionCoordinator
    @Environment(SettingsStore.self) private var settings
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var isTitleFocused: Bool
    @Namespace private var currentRowSpace

    private var presentation: WarmupRampPresentation {
        WarmupRampPresentation(entry: entry, inventory: settings.plateInventory, walk: coordinator.warmupWalk)
    }

    private var pickedTop: Double? {
        coordinator.warmupWalk.pickedTop(forExerciseOrder: entry.exerciseOrder)
    }

    private var rowAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.3)
    }

    var body: some View {
        let presentation = presentation
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    title
                    if let note = presentation.note {
                        noWalk(note)
                    } else {
                        // Spare height parts evenly around the bar, so the rows keep to the thumb's reach.
                        Spacer(minLength: 0)
                        hero(presentation)
                    }
                    Spacer(minLength: 20)
                    foot(presentation)
                }
                .padding(.horizontal)
                .padding(.bottom)
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .animation(rowAnimation, value: presentation.rows.map(\.id))
        .dynamicTypeSize(...Theme.TypeScale.largestSize)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground { palette.paperBackground }
        .task { isTitleFocused = true }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Warm-up")
                .themeFont(.sheetTitle)
                .foregroundStyle(palette.textPrimary)
                .accessibilityFocused($isTitleFocused)
            Text(entry.exerciseTitle)
                .themeFont(.queueName)
                .foregroundStyle(palette.textSecondary)
                // As in the Lens: two lines hold a long name until the size leaves room for a few words.
                .lineLimit(dynamicTypeSize >= .xxLarge ? nil : 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 18)
        .padding(.bottom, 20)
    }

    private func hero(_ presentation: WarmupRampPresentation) -> some View {
        VStack(spacing: 14) {
            BarbellView(perSide: presentation.perSide)

            VStack(spacing: 2) {
                readout(presentation.readout)
                Text(presentation.caption)
                    .themeFont(.fieldLabel)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.barAccessibilityLabel)
        .accessibilityIdentifier("warmup-bar")
    }

    /// The numeral role while the side fits on one line, then a size down, then wrapped, so no load
    /// clips however many plates it takes.
    private func readout(_ text: String) -> some View {
        ViewThatFits(in: .horizontal) {
            Text(text).themeFont(.weightEntry).lineLimit(1)
            Text(text).themeFont(.statsValue).lineLimit(1)
            Text(text).themeFont(.statsValue).multilineTextAlignment(.center)
        }
        .foregroundStyle(palette.textPrimary)
    }

    private func noWalk(_ note: String) -> some View {
        Text(note)
            .themeFont(.coachNote)
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("warmup-note")
    }

    private func foot(_ presentation: WarmupRampPresentation) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(presentation.rows.enumerated()), id: \.element.id) { index, row in
                stepRow(row, index: index, presentation: presentation)
                    .matchedGeometryEffect(id: row.id, in: currentRowSpace)
            }

            if entry.prefill == nil {
                ValueRail(
                    chips: WarmupTopRail.chips(picked: pickedTop),
                    selectedIndex: WarmupTopRail.selectedIndex(picked: pickedTop),
                    label: presentation.setLabel
                ) { label in
                    guard let weight = Double(label) else { return }
                    coordinator.warmupWalk.pick(top: weight, forExerciseOrder: entry.exerciseOrder)
                }
                .padding(.top, presentation.rows.isEmpty ? 0 : 16)
            }
        }
        .background {
            // One capsule behind every row, so it travels to the current row and is never two.
            if let current = presentation.rows.first(where: { $0.state == .current }) {
                Capsule()
                    .fill(palette.actionInk.opacity(0.10))
                    .matchedGeometryEffect(id: current.id, in: currentRowSpace, isSource: false)
            }
        }
        .animation(rowAnimation, value: presentation.rows)
    }

    private func stepRow(_ row: WarmupRampPresentation.Row, index: Int, presentation: WarmupRampPresentation) -> some View {
        Button {
            coordinator.warmupWalk.tap(rowAt: index, of: presentation.steps, forExerciseOrder: entry.exerciseOrder)
        } label: {
            HStack(spacing: 10) {
                // Secondary ink, because a green mark says a Set is logged and a step never is.
                Image(systemName: "checkmark")
                    .themeFont(.queuePill)
                    .foregroundStyle(palette.textSecondary)
                    .opacity(row.state == .finished ? 1 : 0)
                    .accessibilityHidden(true)

                // The heaviest row's width, so the weights stand in one right-aligned column.
                Text(presentation.rows.last?.weight ?? row.weight)
                    .themeFont(.setNumber)
                    .hidden()
                    .overlay(alignment: .trailing) {
                        Text(row.weight)
                            .themeFont(.setNumber)
                            .foregroundStyle(rowInk(row.state))
                    }

                Text(row.detail)
                    .themeFont(.setOf)
                    .foregroundStyle(row.state == .current ? palette.actionInk : palette.textSecondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityValue(row.accessibilityValue)
        .accessibilityIdentifier(row.id)
    }

    private func rowInk(_ state: WarmupRampPresentation.RowState) -> Color {
        switch state {
        case .finished: palette.textSecondary
        case .current: palette.actionInk
        case .ahead: palette.textPrimary
        }
    }
}
