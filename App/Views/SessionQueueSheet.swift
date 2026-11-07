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
    @State private var rowCenters: [String: CGFloat] = [:]
    @State private var wheelHeight: CGFloat = 0
    @AccessibilityFocusState private var isTitleFocused: Bool

    private var isPairing: Bool {
        queue.isPairing
    }

    private var showsOpenExercises: Bool {
        !isPairing && !queue.openExercises.isEmpty
    }

    private var drawsLens: Bool {
        !reduceMotion && !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal)

            wheel

            // The slot holds its frame when Move On is absent, so the wheel's centre never moves.
            SessionMoveOnButton(accessibilityID: "queue-move-on-button") {
                movesOnWhenDismissed = true
                dismiss()
            }
            .visibleKeepingFrame(queue.showsMoveOn && !isPairing)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: queue.pairingMode)
        .animation(reduceMotion ? nil : .spring(duration: 0.32, bounce: 0), value: queue.wheelRows.map(\.id))
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
            VStack(spacing: 0) {
                wheelEndSpace

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(queue.wheelRows) { row in
                        Group {
                            if row.kind == .superset {
                                supersetRow(for: row)
                            } else if isPairing {
                                pairingRow(for: row)
                            } else {
                                queueRow(for: row)
                            }
                        }
                        .onGeometryChange(
                            for: CGFloat.self,
                            of: { $0.frame(in: .named(Self.wheelContent)).midY },
                            action: { rowCenters[row.id] = $0 }
                        )
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

                wheelEndSpace
            }
            .coordinateSpace(.named(Self.wheelContent))
        }
        .scrollIndicators(.hidden)
        .scrollPosition(id: $centeredRowID, anchor: .center)
        .scrollTargetBehavior(
            WheelSnap(rowCenters: queue.wheelRows.compactMap { rowCenters[$0.id] }, freePastLastRow: showsOpenExercises)
        )
        // Sized from the scroll box, so the row is centred against the layout the wheel keeps.
        .onScrollGeometryChange(for: CGFloat.self, of: \.containerSize.height) { _, height in
            wheelHeight = height
            centeredRowID = queue.restingRowID
        }
        .onChange(of: queue.restingRowID) { recenter() }
        .onChange(of: isPairing) { recenter() }
        .mask {
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [.init(color: .clear, location: 0.2), .init(color: .black, location: 1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: Self.edgeFade)
                Color.black
                LinearGradient(
                    stops: [.init(color: .black, location: 0), .init(color: .clear, location: 0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: Self.edgeFade)
            }
        }
    }

    /// Half the wheel's height past each end, so any row, however tall, can rest on the centre. These
    /// are views and not content margins, which would shrink the scroll view's box to one row's height.
    private var wheelEndSpace: some View {
        Color.clear.frame(height: wheelHeight / 2)
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
                .padding(.leading, Self.textInset)

            Spacer(minLength: 12)

            if !isPairing, let entry = queue.warmupEntry {
                WarmupRampButton(entry: entry, coordinator: coordinator, size: Self.headerButtonSize)
            }

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
                EmptyView()
            }
            .padding(.trailing, Self.unlinkButtonSize)
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
            if row.wearsCapsule {
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
            QueueRowFace(row: row, drawsLens: drawsLens)
                .padding(.leading, Self.textInset)

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 12)
            }

            trailing()
        }
        .padding(.horizontal)
        .padding(.vertical, Self.rowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
        .contentShape(Rectangle())
    }

    private static let wheelContent = "wheel-content"
    fileprivate static let rowHeight: CGFloat = 64
    fileprivate static let rowVerticalPadding: CGFloat = 12
    private static let capsuleInset: CGFloat = 8
    private static let textInset: CGFloat = 6
    private static let edgeFade: CGFloat = 40
}

/// A row's name and Set marks. Only the face shrinks, so every row keeps its full-size hit area and
/// its capsule.
private struct QueueRowFace: View {
    let row: SessionQueue.Row
    let drawsLens: Bool
    @Environment(\.themePalette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if row.kind == .superset {
                SupersetStemGlyph(form: .linked, color: palette.actionInk)
                    .frame(width: 20, height: 20)
                    .alignmentGuide(.firstTextBaseline) { $0.height * 0.8 }
                    .accessibilityLabel("Superset")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(row.title)
                    .themeFont(row.isOnStage ? .queueNameOnStage : .queueName)
                    .foregroundStyle(nameColor)
                    // Two lines hold a long name at the default size; from xxLarge they hold a few
                    // words, so the row grows instead.
                    .lineLimit(dynamicTypeSize >= .xxLarge ? nil : 2)
                    .minimumScaleFactor(row.isOnStage ? 20 / 24 : 1)
                    .truncationMode(row.kind == .superset ? .middle : .tail)
                    .fixedSize(horizontal: false, vertical: true)

                QueueSetMarks(groups: row.exerciseSets)
            }
        }
        .visualEffect { [drawsLens] effect, proxy in
            guard drawsLens else { return effect.scaleEffect(1, anchor: .leading) }
            let wheelCenter = proxy.bounds(of: .scrollView)?.midY ?? proxy.size.height / 2
            let rowHeight = max(SessionQueueSheet.rowHeight, proxy.size.height + 2 * SessionQueueSheet.rowVerticalPadding)
            let scale = SessionQueue.lensScale(distance: proxy.size.height / 2 - wheelCenter, rowHeight: rowHeight)
            return effect.scaleEffect(scale, anchor: .leading)
        }
    }

    private var nameColor: Color {
        if row.isOnStage { return palette.actionInk }
        return row.isComplete ? palette.textSecondary : palette.textPrimary
    }
}

/// Rests a row's centre on the wheel's. `ViewAlignedScrollTargetBehavior(anchor: .center)` puts a row's
/// top there instead.
private struct WheelSnap: ScrollTargetBehavior {
    let rowCenters: [CGFloat]
    let freePastLastRow: Bool

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let center = SessionQueue.restingCenter(
            near: target.rect.midY,
            rowCenters: rowCenters.map(Double.init),
            freePastLastRow: freePastLastRow
        )
        if let center { target.rect.origin.y = center - target.rect.height / 2 }
    }
}

extension View {
    fileprivate func dimmedWhenUnavailable(_ role: QueuePairingRole) -> some View {
        opacity(role == .ineligibleTarget ? Theme.pairingUnavailableOpacity : 1)
    }

    fileprivate func rowAccessibility(_ row: SessionQueue.Row) -> some View {
        accessibilityValue(row.pairingRole == .ineligibleTarget ? "Unavailable" : row.sets.spokenProgress)
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
