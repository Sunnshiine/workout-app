import SwiftUI

/// The Lens's way to the ramp. It presents the sheet, so the sheet leaves when the entry does.
struct WarmupRampButton: View {
    let entry: WarmupEntry
    let coordinator: SessionCoordinator
    let size: CGFloat
    @Environment(\.themePalette) private var palette
    @State private var isPresented = false

    var body: some View {
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

/// The walk up to a Set: a drawn bar with exactly what goes on each side, and the steps beneath it. A
/// tap marks a step for this Session alone. Nothing here reaches the card or the Sheet.
struct WarmupRampSheet: View {
    let entry: WarmupEntry
    let coordinator: SessionCoordinator
    @Environment(SettingsStore.self) private var settings
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var isTitleFocused: Bool

    private var presentation: WarmupRampPresentation {
        WarmupRampPresentation(entry: entry, inventory: settings.plateInventory, walk: coordinator.warmupWalk)
    }

    private var pickedTop: Double? {
        coordinator.warmupWalk.pickedTop(forExerciseOrder: entry.exerciseOrder)
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
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: presentation.rows.map(\.id))
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
                .themeFont(.runlineSecondary)
                .foregroundStyle(palette.textSecondary)
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
        .contentTransition(reduceMotion ? .identity : .numericText())
        .animation(reduceMotion ? nil : BarbellView.loadAnimation, value: text)
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
    }

    private func stepRow(_ row: WarmupRampPresentation.Row, index: Int, presentation: WarmupRampPresentation) -> some View {
        Button {
            coordinator.warmupWalk.tap(rowAt: index, of: presentation.steps, forExerciseOrder: entry.exerciseOrder)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .themeFont(.queuePill)
                    .foregroundStyle(palette.action)
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
            .background {
                if row.state == .current {
                    Capsule().fill(palette.actionInk.opacity(0.10))
                }
            }
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
