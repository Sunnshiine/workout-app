import SwiftUI

struct MeetPlatformView: View {
    @Environment(MeetStore.self) private var store
    @Environment(\.themePalette) private var palette

    var body: some View {
        Group {
            if let meet = store.meet {
                content(meet)
            }
        }
        .background {
            palette.paperBackground
                .overlay { palette.lighting.pageSunbeam?.gradientView }
                .ignoresSafeArea()
        }
        .navigationTitle("Platform")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.isPlatformOnScreen = true }
        .onDisappear { store.isPlatformOnScreen = false }
    }

    @ViewBuilder
    private func content(_ meet: Meet) -> some View {
        let stage = meet.stage(at: store.now())
        ZStack {
            switch stage {
            case .noAttempts:
                EmptyView()
            case .onDeck(let deck):
                MeetOnDeckView(deck: deck, meet: meet)
                    .transition(MeetStageTransition.quiet)
            case .window:
                if let window = meet.attemptWindow {
                    MeetAttemptWindowView(window: window)
                        .transition(MeetStageTransition.quiet)
                }
            case .finished:
                MeetFinishedView(meet: meet)
                    .transition(MeetStageTransition.quiet)
            }
        }
        .animation(.easeOut(duration: Theme.Motion.crossfade), value: MeetStageTransition.key(stage))
    }
}

enum MeetStageTransition {
    static var quiet: AnyTransition {
        .asymmetric(insertion: .opacity, removal: .opacity.animation(.easeOut(duration: 0.15)))
    }

    /// Only a change of stage animates. A step of the count or a second of the window does not.
    static func key(_ stage: MeetStage) -> String {
        switch stage {
        case .noAttempts: "none"
        case .onDeck(let deck): "deck-\(deck.lift.rawValue)-\(deck.ordinal.rawValue)"
        case .window(let window): "window-\(window.lift.rawValue)-\(window.ordinal.rawValue)"
        case .finished: "finished"
        }
    }
}

// MARK: - The numeral every stage reads from

struct MeetReadout: View {
    let caption: String
    let numeral: String
    let unit: String?
    let beneath: String?
    let countsDown: Bool
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            Text(caption)
                .themeFont(.heading)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(numeral)
                    .themeFont(.countdownNumeral)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: countsDown))
                    .animation(.snappy(duration: 0.2), value: numeral)
                if let unit {
                    Text(unit)
                        .themeFont(.statsValue)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            if let beneath {
                Text(beneath)
                    .themeFont(.heading)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

/// The room between a stage's lift and its numeral. It stops growing, so the numeral holds its place
/// when a stage's controls change at the foot of the page.
private struct MeetReadoutGap: View {
    var body: some View {
        Spacer(minLength: 8)
            .frame(maxHeight: 72)
    }
}

// MARK: - Waiting on an Attempt

private struct MeetOnDeckView: View {
    let deck: AttemptOnDeck
    let meet: Meet
    @Environment(MeetStore.self) private var store
    @Environment(\.themePalette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isChanging = false

    private var face: MeetOnDeckFace { MeetOnDeckFace(deck, rules: meet.rules) }

    var body: some View {
        let face = face
        MeetFullPage {
            VStack(spacing: Theme.cardSpacing) {
                MeetLiftHeader(lift: meet.lift(deck.lift))
                if let note = face.intervalNote {
                    Text(note)
                        .themeFont(.coachNote)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("meet-interval-note")
                }
                MeetReadoutGap()
                readout(face)
                Spacer(minLength: Theme.cardSpacing)
                changeRow(face)
                control(face)
            }
        }
        .sheet(isPresented: $isChanging) {
            MeetWeightSheet(
                title: face.place,
                entry: MeetWeightEntry(deck.kilograms, rules: meet.rules),
                saveLabel: "Change to",
                onClear: nil
            ) { weight in
                try? store.changeOnDeck(to: weight)
            }
        }
    }

    private func readout(_ face: MeetOnDeckFace) -> some View {
        VStack(spacing: 12) {
            MeetReadout(caption: face.caption, numeral: face.numeral, unit: "kg", beneath: face.pounds, countsDown: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(face.accessibilitySummary)
                .accessibilityIdentifier("meet-readout")
            Text(face.detail)
                .themeFont(.coachNote)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func changeRow(_ face: MeetOnDeckFace) -> some View {
        HStack(spacing: 10) {
            if let changeLabel = face.changeLabel {
                Button {
                    isChanging = true
                } label: {
                    Text(changeLabel)
                        .footPill(palette)
                }
                .buttonStyle(.pressScale)
                .accessibilityIdentifier("meet-change-attempt")
            }
            if store.canUndoMark {
                MeetUndoPill()
            }
        }
    }

    @ViewBuilder
    private func control(_ face: MeetOnDeckFace) -> some View {
        if face.isOnThePlatform {
            MeetMarkButtons(attemptsOut: deck.attemptsOut)
        } else {
            MeetAttemptsOutStepper(numeral: face.attemptsOutNumeral, label: face.attemptsOutLabel, count: deck.attemptsOut)
        }
    }
}

/// The pads are the widest the page allows and taller than any other control, for a chalky thumb
/// that does not look.
private struct MeetAttemptsOutStepper: View {
    let numeral: String
    let label: String
    let count: Int
    @Environment(MeetStore.self) private var store
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let padHeight: CGFloat = 88

    var body: some View {
        HStack(spacing: 12) {
            pad(direction: .decrement, label: "One attempt fewer", identifier: "meet-attempts-out-down") { step(-1) }
            VStack(spacing: 0) {
                Text(numeral)
                    .themeFont(.weightEntry)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(reduceMotion ? .opacity : .numericText(countsDown: true))
                    .animation(.snappy(duration: 0.2), value: numeral)
                Text(label)
                    .themeFont(.fieldLabel)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(minWidth: 84)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("meet-attempts-out-value")
            pad(direction: .increment, label: "One attempt more", identifier: "meet-attempts-out-up") { step(1) }
        }
    }

    private func pad(
        direction: WeightStepperButton.Direction,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: direction == .decrement ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(palette.stepperGlyph)
                .frame(width: 24, height: 24)
                .offset(y: direction == .decrement ? 2 : -2)
                .frame(maxWidth: .infinity)
                .frame(height: Self.padHeight)
                .background(palette.pillFill, in: .capsule)
                .themeElevation(palette.lighting.raisedControlShadow, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.pressScale)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private func step(_ change: Int) {
        HapticPlayer.shared.play(.input(Theme.Haptics.stepperTick))
        store.setAttemptsOut(count + change)
    }
}

private struct MeetMarkButtons: View {
    let attemptsOut: Int
    @Environment(MeetStore.self) private var store
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(spacing: 12) {
            Button {
                mark(.good)
            } label: {
                Label("Good lift", systemImage: "checkmark")
                    .logCapsuleMetrics()
                    .foregroundStyle(palette.actionText)
                    .background(palette.actionFill, in: .capsule)
            }
            .buttonStyle(.pressScale)
            .accessibilityIdentifier("meet-mark-good")
            Button {
                mark(.noLift)
            } label: {
                Label("No lift", systemImage: "xmark")
                    .logCapsuleMetrics()
                    .foregroundStyle(palette.textPrimary)
                    .background(palette.pillFill, in: .capsule)
                    .themeElevation(palette.lighting.raisedControlShadow, in: Capsule())
            }
            .buttonStyle(.pressScale)
            .accessibilityIdentifier("meet-mark-no-lift")
            Button {
                store.setAttemptsOut(attemptsOut + 1)
            } label: {
                Text("Not yet")
                    .footPill(palette)
            }
            .buttonStyle(.pressScale)
            .accessibilityHint("Sets one attempt out")
            .accessibilityIdentifier("meet-not-yet")
        }
    }

    private func mark(_ result: AttemptResult) {
        HapticPlayer.shared.play(.input(Theme.Haptics.logTap))
        try? store.mark(result)
    }
}

struct MeetUndoPill: View {
    @Environment(MeetStore.self) private var store
    @Environment(\.themePalette) private var palette

    var body: some View {
        Button {
            store.undoMark()
        } label: {
            Label("Undo", systemImage: "arrow.uturn.backward")
                .footPill(palette)
        }
        .buttonStyle(.pressScale)
        .accessibilityLabel("Undo the last mark")
        .accessibilityIdentifier("meet-undo")
    }
}

// MARK: - The Attempt Window

private struct MeetAttemptWindowView: View {
    let window: AttemptWindow
    @Environment(MeetStore.self) private var store

    var body: some View {
        TimelineView(.periodic(from: window.startedAt, by: 1)) { _ in
            if let meet = store.meet, case .window(let open) = meet.stage(at: store.now()) {
                MeetAttemptWindowFaceView(
                    face: AttemptWindowFace(open, windowSeconds: window.seconds),
                    open: open,
                    rules: meet.rules
                )
            }
        }
    }
}

private struct MeetAttemptWindowFaceView: View {
    let face: AttemptWindowFace
    let open: OpenAttemptWindow
    let rules: FederationRules
    @Environment(MeetStore.self) private var store
    @Environment(\.themePalette) private var palette
    @State private var entry: MeetWeightEntry

    init(face: AttemptWindowFace, open: OpenAttemptWindow, rules: FederationRules) {
        self.face = face
        self.open = open
        self.rules = rules
        _entry = State(initialValue: MeetWeightEntry(open.planned ?? open.tableEntry, rules: rules))
    }

    private var previous: (kilograms: Kilograms, result: AttemptResult) { (open.marked, open.result) }

    var body: some View {
        MeetFullPage {
            VStack(spacing: Theme.cardSpacing) {
                MeetLiftHeader(lift: store.meet?.lift(open.lift) ?? .empty(open.lift))
                MeetReadoutGap()
                readout
                Spacer(minLength: Theme.cardSpacing)
                MeetWeightStepper(entry: $entry, label: face.attemptLabel, spokenLabel: "\(face.attemptLabel) in kilograms")
                noteLine
                actions
            }
        }
        .onChange(of: face.stage) { _, stage in
            feel(stage)
        }
    }

    private var readout: some View {
        VStack(spacing: 10) {
            Text(face.markLine)
                .themeFont(.runline)
                .foregroundStyle(palette.textSecondary)
            MeetReadout(caption: face.caption, numeral: face.numeral, unit: nil, beneath: nil, countsDown: true)
            windowBar
            // The room stays held, so the numeral above does not move when the rule arrives.
            Text(face.rule)
                .themeFont(.logCapsule)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
                .opacity(face.showsRule ? 1 : 0)
                .animation(.easeOut(duration: Theme.Motion.crossfade), value: face.showsRule)
                .accessibilityIdentifier("meet-window-rule")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(face.markLine)
        .accessibilityValue(face.accessibilityValue)
        .accessibilityIdentifier("meet-window")
    }

    private var windowBar: some View {
        Capsule()
            .fill(palette.railFill)
            .frame(width: 160, height: 6)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(palette.action)
                    .frame(width: 160 * face.remaining)
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var noteLine: some View {
        MeetWeightNoteView(note: entry.note(after: previous))
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            if face.stage == .expired {
                expiredActions
            } else {
                submitButton
            }
            HStack(spacing: 10) {
                if store.canUndoMark {
                    MeetUndoPill()
                }
                Button {
                    try? store.pass()
                } label: {
                    Text("Pass")
                        .footPill(palette)
                }
                .buttonStyle(.pressScale)
                .accessibilityLabel("Pass the rest of this lift")
                .accessibilityIdentifier("meet-pass")
            }
        }
    }

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            MeetCapsuleLabel(
                text: entry.kilograms.map { "Submit \($0.label)" } ?? "Submit",
                canAct: entry.canSave(after: previous)
            )
        }
        .buttonStyle(.pressScale)
        .disabled(!entry.canSave(after: previous))
        .accessibilityIdentifier("meet-submit")
    }

    /// The phone cannot see a card reach the table, so it asks, and either answer submits.
    @ViewBuilder
    private var expiredActions: some View {
        Button {
            HapticPlayer.shared.play(.input(Theme.Haptics.logTap))
            try? store.acceptTableEntry()
        } label: {
            Text("The table entered \(open.tableEntry.label)")
                .logCapsuleMetrics()
                .foregroundStyle(palette.actionText)
                .background(palette.actionFill, in: .capsule)
        }
        .buttonStyle(.pressScale)
        .accessibilityIdentifier("meet-accept-table-entry")
        if let handedIn = entry.kilograms, handedIn != open.tableEntry, entry.canSave(after: previous) {
            Button {
                submit()
            } label: {
                Text("I handed in \(handedIn.label)")
                    .footPill(palette)
            }
            .buttonStyle(.pressScale)
            .accessibilityIdentifier("meet-handed-in")
        }
    }

    private func submit() {
        guard let weight = entry.kilograms else { return }
        HapticPlayer.shared.play(.input(Theme.Haptics.logTap))
        try? store.submitNext(weight)
    }

    private func feel(_ stage: AttemptWindowFace.Stage) {
        switch stage {
        case .open:
            break
        case .closing:
            HapticPlayer.shared.play(.rest(.lightTap))
            AccessibilityNotification.Announcement(face.rule).post()
        case .expired:
            HapticPlayer.shared.play(.rest(.expiryBuzz))
            AccessibilityNotification.Announcement(face.accessibilityValue).post()
        }
    }
}

// MARK: - The day done

private struct MeetFinishedView: View {
    let meet: Meet
    @Environment(MeetStore.self) private var store
    @Environment(\.themePalette) private var palette

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                total
                VStack(spacing: Theme.cardSpacing) {
                    ForEach(meet.lifts.filter { !$0.attempts.isEmpty }, id: \.lift) { lift in
                        MeetLiftHeader(lift: lift)
                    }
                }
                .frame(maxWidth: .infinity)
                if store.canUndoMark {
                    MeetUndoPill()
                }
            }
            .padding(Theme.pageMargin)
        }
    }

    @ViewBuilder
    private var total: some View {
        if let total = meet.total {
            MeetReadout(caption: "Total", numeral: total.numeral, unit: "kg", beneath: total.poundsLabel, countsDown: false)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("meet-total")
        } else {
            VStack(spacing: 6) {
                Text("No total")
                    .themeFont(.weightEntry)
                    .foregroundStyle(palette.textPrimary)
                Text("A lift with no good attempt leaves no total.")
                    .themeFont(.coachNote)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("meet-total")
        }
    }
}
