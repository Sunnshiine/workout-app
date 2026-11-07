import SwiftUI

/// The full Session queue in a medium sheet: a wheel that rests on the Exercise on stage, finished
/// rows above it and the rows left below, each with a mark per Set. Move On is pinned under the wheel
/// when the Session can advance. Tapping a row brings it on stage, a finished one with its logged Set
/// open for review.
struct SessionQueueSheet: View {
    let queue: SessionQueue
    let session: Session
    let coordinator: SessionCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var movesOnWhenDismissed = false
    @State private var centeredRowID: String?
    @State private var wheelHeight: CGFloat = 0
    @AccessibilityFocusState private var isTitleFocused: Bool

    private var isPairing: Bool {
        queue.isPairing
    }

    private var showsOpenExercises: Bool {
        !isPairing && !queue.openExercises.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal)

            wheel

            if queue.showsMoveOn, !isPairing {
                SessionMoveOnButton(accessibilityID: "queue-move-on-button") {
                    movesOnWhenDismissed = true
                    dismiss()
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
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

    private var wheel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(queue.wheelRows) { row in
                    if row.kind == .superset {
                        supersetRow(for: row)
                    } else if isPairing {
                        pairingRow(for: row)
                    } else {
                        queueRow(for: row)
                    }
                }

                if showsOpenExercises {
                    OpenExercisesSection(exercises: queue.openExercises) { exercise in
                        dismiss()
                        coordinator.showSourceSession(of: exercise)
                    }
                    .padding(.horizontal)
                    .padding(.top, Theme.cardSpacing)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .contentMargins(.vertical, max(0, (wheelHeight - Self.rowHeight) / 2), for: .scrollContent)
        .scrollPosition(id: $centeredRowID, anchor: .center)
        .scrollTargetBehavior(WheelSnap(snaps: !showsOpenExercises))
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
            wheelHeight = height
            if centeredRowID == nil { centeredRowID = queue.restingRowID }
        }
        .onChange(of: queue.restingRowID) { recenter() }
        .onChange(of: isPairing) { recenter() }
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.edgeFade)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.edgeFade)
            }
        }
    }

    private func recenter() {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.32, bounce: 0)) { centeredRowID = queue.restingRowID }
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
                EmptyView()
            }
        }
        .buttonStyle(.plain)
        .disabled(row.jumpTarget == nil)
        .rowAccessibility(row)
    }

    private func jump(to row: SessionQueue.Row) {
        dismiss()
        if let target = row.jumpTarget {
            coordinator.jump(to: target)
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
            rowLabel(for: row) {
                Color.clear.frame(width: Self.unlinkButtonSize)
            }
        }
        .buttonStyle(.plain)
        .disabled(row.jumpTarget == nil)
        .background(Capsule().fill(palette.surface).padding(.horizontal, Self.capsuleInset))
        .dimmedWhenUnavailable(row.pairingRole)
        .rowAccessibility(row)
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
            .padding(.trailing, Self.capsuleInset + 4)
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
                Capsule().fill(palette.actionInk.opacity(0.10)).padding(.horizontal, Self.capsuleInset)
            }
        }
        .overlay {
            if row.pairingRole == .source {
                Capsule().strokeBorder(palette.actionInk, lineWidth: 2).padding(.horizontal, Self.capsuleInset)
            }
        }
        .rowAccessibility(row)
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
            rowFace(for: row)

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 12)
            }

            trailing()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// Only the face shrinks, so every row keeps its full-size hit area and its capsule.
    private func rowFace(for row: SessionQueue.Row) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if row.kind == .superset {
                    SupersetStemGlyph(form: .linked, color: palette.actionInk)
                        .frame(width: 20, height: 20)
                        .accessibilityLabel("Superset")
                }

                Text(row.title)
                    .themeFont(row.isOnStage ? .queueNameOnStage : .queueName)
                    .foregroundStyle(nameColor(for: row))
                    // Two lines hold a long name at the default size; at an accessibility size
                    // they hold two words, so the row grows instead.
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .minimumScaleFactor(row.isOnStage ? 20 / 24 : 1)
                    .truncationMode(row.kind == .superset ? .middle : .tail)
                    .fixedSize(horizontal: false, vertical: true)
            }

            QueueSetMarks(sets: row.sets)
        }
        .visualEffect { [reduceMotion] effect, proxy in
            let wheelCenter = proxy.bounds(of: .scrollView)?.midY ?? proxy.size.height / 2
            let rowsFromCenter = (proxy.size.height / 2 - wheelCenter) / Self.rowHeight
            let scale = reduceMotion ? 1 : SessionQueue.lensScale(rowsFromCenter: rowsFromCenter)
            return effect.scaleEffect(scale, anchor: .leading)
        }
    }

    private func nameColor(for row: SessionQueue.Row) -> Color {
        if row.isOnStage { return palette.actionInk }
        return row.isComplete ? palette.textSecondary : palette.textPrimary
    }

    private static let rowHeight: CGFloat = 64
    private static let capsuleInset: CGFloat = 4
    private static let edgeFade: CGFloat = 24
}

/// Rests a row on the wheel's centre. Open Exercises scroll free, since one taller than the sheet
/// would otherwise snap away from its own end.
private struct WheelSnap: ScrollTargetBehavior {
    let snaps: Bool

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard snaps else { return }
        ViewAlignedScrollTargetBehavior(anchor: .center).updateTarget(&target, context: context)
    }
}

extension View {
    fileprivate func dimmedWhenUnavailable(_ role: QueuePairingRole) -> some View {
        opacity(role == .ineligibleTarget ? Theme.pairingUnavailableOpacity : 1)
    }

    fileprivate func rowAccessibility(_ row: SessionQueue.Row) -> some View {
        accessibilityValue(row.pairingRole == .ineligibleTarget ? "Unavailable" : row.spokenSets)
            .accessibilityAddTraits(row.isOnStage ? .isSelected : [])
            .accessibilityIdentifier("stage-queue-row-\(row.id)")
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
