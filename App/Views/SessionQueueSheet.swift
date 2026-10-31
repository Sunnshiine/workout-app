import SwiftUI

/// The full Session queue in a medium sheet: every stage item in Session order
/// with its Set dots, the one on stage marked "Now", and Move On in the footer
/// when the Session can advance. Tapping a row brings it on stage, a finished one with its logged
/// Set open for review.
struct SessionQueueSheet: View {
    let queue: SessionQueue
    let session: Session
    let coordinator: SessionCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var movesOnWhenDismissed = false
    @State private var isScrolled = false
    @AccessibilityFocusState private var isTitleFocused: Bool

    private var isPairing: Bool {
        queue.isPairing
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal)

            rows
        }
        .animation(.easeInOut(duration: 0.18), value: queue.pairingMode)
        .animation(reduceMotion ? nil : .spring(duration: 0.32, bounce: 0), value: queue.rows.map(\.id))
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground { palette.paperBackground }
        .task { isTitleFocused = true }
        .onDisappear {
            coordinator.cancelPairing()
            if movesOnWhenDismissed { coordinator.moveOn() }
        }
    }

    private var rows: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(queue.rows) { row in
                    if row.kind == .superset {
                        supersetRow(for: row)
                    } else if isPairing {
                        pairingRow(for: row)
                    } else {
                        queueRow(for: row)
                    }
                }

                if !isPairing, !queue.openExercises.isEmpty {
                    OpenExercisesSection(exercises: queue.openExercises) { exercise in
                        dismiss()
                        coordinator.showSourceSession(of: exercise)
                    }
                    .padding(.top, Theme.cardSpacing)
                }

                if queue.showsMoveOn, !isPairing {
                    SessionMoveOnButton(accessibilityID: "queue-move-on-button") {
                        movesOnWhenDismissed = true
                        dismiss()
                    }
                    .padding(.top, Theme.cardSpacing)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .safeAreaPadding(.top, 8)
        .onScrollGeometryChange(for: Bool.self) {
            $0.contentOffset.y + $0.contentInsets.top > 0
        } action: {
            isScrolled = $1
        }
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [isScrolled ? .clear : .black, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 16)
                Color.black
            }
        }
    }

    private var header: some View {
        HStack {
            Text("This Session")
                .themeFont(.sheetTitle)
                .foregroundStyle(palette.textPrimary)
                .accessibilityFocused($isTitleFocused)

            Spacer(minLength: 12)

            if isPairing || queue.supersetSource != nil {
                supersetHeaderButton
            }
        }
        .frame(minHeight: Self.headerButtonSize)
        .padding(.top, 18)
    }

    private var supersetHeaderButton: some View {
        Button {
            if isPairing {
                coordinator.cancelPairing()
            } else if let source = queue.supersetSource {
                coordinator.beginPairing(from: source.pairingExercise, in: session)
            }
        } label: {
            Group {
                if isPairing {
                    Image(systemName: "xmark")
                        .themeFont(.queuePill)
                        .foregroundStyle(palette.textSecondary)
                } else {
                    SupersetStemGlyph(form: .begin, color: palette.actionInk)
                        .frame(width: 24, height: 24)
                }
            }
            .frame(width: Self.headerButtonSize, height: Self.headerButtonSize)
            .background(Circle().fill(palette.pillFill))
            .themeElevation(palette.lighting.raisedControlShadow, in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPairing ? "Cancel Superset" : "Superset")
        .accessibilityHint(isPairing ? "" : queue.supersetSource.map { "Pick an Exercise to pair with \($0.title)" } ?? "")
        .accessibilityIdentifier(isPairing ? "stage-queue-cancel-pairing" : "stage-queue-superset")
    }

    private static let headerButtonSize: CGFloat = 46

    // MARK: - Browsing

    private func queueRow(for row: SessionQueue.Row) -> some View {
        Button {
            jump(to: row)
        } label: {
            rowLabel(for: row) {
                nowLabel(for: row)
            }
        }
        .buttonStyle(.plain)
        .disabled(row.jumpTarget == nil)
        .accessibilityIdentifier("stage-queue-row-\(row.id)")
    }

    private func jump(to row: SessionQueue.Row) {
        dismiss()
        if let target = row.jumpTarget {
            coordinator.jump(to: target)
        }
    }

    @ViewBuilder
    private func nowLabel(for row: SessionQueue.Row) -> some View {
        if row.isOnStage {
            Text("Now")
                .themeFont(.fieldLabel)
                .foregroundStyle(palette.actionInk)
        }
    }

    private func supersetRow(for row: SessionQueue.Row) -> some View {
        Button {
            if isPairing {
                pick(row)
            } else {
                jump(to: row)
            }
        } label: {
            HStack(spacing: 0) {
                SupersetStemGlyph(form: .linked, color: palette.actionInk)
                    .frame(width: 26, height: 26)
                    .accessibilityLabel("Superset")
                    .padding(.leading, 14)

                rowLabel(for: row) {
                    nowLabel(for: row)
                }
            }
            .padding(.trailing, Self.unlinkButtonSize + 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(row.jumpTarget == nil)
        .background(Capsule().fill(palette.surface))
        .dimmedWhenUnavailable(row.pairingRole)
        .accessibilityIdentifier("stage-queue-row-\(row.id)")
        .overlay(alignment: .trailing) {
            Button {
                coordinator.dismissSuperset(containing: row.pairingExercise, in: session)
            } label: {
                SupersetStemGlyph(form: .unlink, color: palette.textSecondary)
                    .frame(width: 26, height: 26)
                    .frame(width: Self.unlinkButtonSize, height: Self.unlinkButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
            .accessibilityLabel("Unlink Superset")
            .accessibilityIdentifier("stage-queue-unlink-\(row.id)")
            .visibleKeepingFrame(!isPairing)
        }
    }

    private static let unlinkButtonSize: CGFloat = 46

    // MARK: - Pairing

    private func pairingRow(for row: SessionQueue.Row) -> some View {
        Button {
            pick(row)
        } label: {
            rowLabel(for: row) {
                pairingGlyph(for: row.pairingRole)
                    .frame(width: 26, height: 26)
                    .frame(width: 46, height: 30)
            }
        }
        .buttonStyle(.plain)
        .dimmedWhenUnavailable(row.pairingRole)
        .background {
            if row.pairingRole == .source || row.pairingRole == .confirmingTarget {
                Capsule().fill(palette.actionInk.opacity(0.10))
            }
        }
        .overlay {
            if row.pairingRole == .source {
                Capsule().strokeBorder(palette.actionInk, lineWidth: 2)
            }
        }
        .accessibilityIdentifier("stage-queue-row-\(row.id)")
    }

    private func pick(_ row: SessionQueue.Row) {
        if coordinator.handlePairingTap(on: row.pairingExercise, in: session) == .unavailable {
            HapticPlayer.shared.play(.warning)
        }
    }

    @ViewBuilder
    private func pairingGlyph(for role: QueuePairingRole) -> some View {
        switch role {
        case .source:
            SupersetStemGlyph(form: .begin, color: palette.actionInk)
                .accessibilityLabel("Selected for Superset")
        case .confirmingTarget:
            SupersetStemGlyph(form: .linked, color: palette.actionInk)
                .accessibilityLabel("Selected for Superset")
        case .eligibleTarget:
            SupersetStemGlyph(form: .partner, color: palette.actionInk)
                .accessibilityLabel(queue.pairingSource.map { "Superset with \($0.title)" } ?? "Superset")
        case .none, .ineligibleTarget:
            EmptyView()
        }
    }

    // MARK: - Row label

    /// At an accessibility text size the trailing mark takes the name's width, so it sits below.
    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    private func rowLabel(for row: SessionQueue.Row, @ViewBuilder trailing: () -> some View) -> some View {
        rowLayout {
            VStack(alignment: .leading, spacing: 6) {
                Text(row.title)
                    .themeFont(.queuePill)
                    .foregroundStyle(row.isComplete ? palette.textSecondary : palette.textPrimary)
                    // Two lines hold a long name at the default size; at an accessibility size
                    // they hold two words, so the row grows instead.
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                SessionStageSetDots(sets: row.sets)
            }

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 12)
            }

            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

extension View {
    fileprivate func dimmedWhenUnavailable(_ role: QueuePairingRole) -> some View {
        let isUnavailable = role == .ineligibleTarget
        return opacity(isUnavailable ? Theme.pairingUnavailableOpacity : 1)
            .accessibilityValue(isUnavailable ? "Unavailable" : "")
    }

    fileprivate func visibleKeepingFrame(_ isShown: Bool) -> some View {
        hidden().overlay {
            if isShown {
                self
            }
        }
    }
}

private struct SupersetStemGlyph: View {
    enum Form { case begin, partner, linked, unlink }
    let form: Form
    let color: Color

    var body: some View {
        Canvas { context, size in
            let s = size.width / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            let solid = StrokeStyle(lineWidth: 2.2 * s, lineCap: .round, lineJoin: .round)
            let dashed = StrokeStyle(lineWidth: 2.2 * s, lineCap: .round, dash: [2.4 * s, 3 * s])

            func leaf(at c: CGPoint, filled: Bool) {
                let r = 3.6 * s
                let path = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                if filled {
                    context.fill(path, with: .color(color))
                } else {
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2 * s))
                }
            }

            var lateral = Path()
            lateral.move(to: p(9, 15))
            lateral.addQuadCurve(to: p(17.5, 8.5), control: p(15, 15))

            if form != .partner {
                var main = Path()
                main.move(to: p(9, 22))
                main.addLine(to: p(9, 7.5))
                context.stroke(main, with: .color(color), style: solid)
                leaf(at: p(9, 4.5), filled: true)
            }

            switch form {
            case .begin:
                context.stroke(lateral, with: .color(color), style: dashed)
                leaf(at: p(19, 6.5), filled: false)
            case .partner:
                var reach = Path()
                reach.move(to: p(4, 20))
                reach.addQuadCurve(to: p(13.6, 11.6), control: p(11, 20))
                context.stroke(reach, with: .color(color), style: solid)
                let bud = CGRect(x: 12.2 * s, y: 2.2 * s, width: 10.6 * s, height: 10.6 * s)
                context.stroke(Path(ellipseIn: bud), with: .color(color), style: StrokeStyle(lineWidth: 2 * s))
                var plus = Path()
                plus.move(to: p(17.5, 5))
                plus.addLine(to: p(17.5, 10))
                plus.move(to: p(15, 7.5))
                plus.addLine(to: p(20, 7.5))
                context.stroke(plus, with: .color(color), style: StrokeStyle(lineWidth: 1.6 * s, lineCap: .round))
            case .linked:
                context.stroke(lateral, with: .color(color), style: solid)
                leaf(at: p(19, 6.5), filled: true)
            case .unlink:
                var broken = Path()
                broken.move(to: p(13.5, 15.5))
                broken.addQuadCurve(to: p(20, 10), control: p(18, 15.5))
                context.stroke(broken, with: .color(color), style: solid)
                leaf(at: p(21, 7.5), filled: true)
            }
        }
        .accessibilityElement()
    }
}
