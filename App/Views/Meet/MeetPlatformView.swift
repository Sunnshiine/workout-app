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
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.isPlatformOnScreen = true }
        .onDisappear { store.isPlatformOnScreen = false }
    }

    @ViewBuilder
    private func content(_ meet: Meet) -> some View {
        let stage = meet.stage(at: store.now())
        let key = MeetStageTransition.key(stage)
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
        .animation(.easeOut(duration: Theme.Motion.crossfade), value: key)
        .meetSettles(on: key)
        .onChange(of: key) {
            if case .finished = stage, meet.total != nil {
                HapticPlayer.shared.play(.moveOn)
            }
        }
    }
}

enum MeetStageTransition {
    static var quiet: AnyTransition {
        .asymmetric(insertion: .opacity, removal: .opacity.animation(.easeOut(duration: 0.15)))
    }

    /// Only a change of stage animates, reaching the platform included. A step of the count or a
    /// second of the window does not.
    static func key(_ stage: MeetStage) -> String {
        switch stage {
        case .noAttempts: "none"
        case .onDeck(let deck): "deck-\(deck.lift.rawValue)-\(deck.ordinal.rawValue)-\(deck.attemptsOut == 0)"
        case .window(let window): "window-\(window.lift.rawValue)-\(window.ordinal.rawValue)"
        case .finished: "finished"
        }
    }
}

// MARK: - The numeral every stage reads from

/// Only the page's width can shrink it, so a bar weight never reads smaller than a warm-up's for want
/// of height. A page too tall for the screen scrolls instead.
struct MeetNumeral: View {
    let numeral: String
    let unit: String?
    let countsDown: Bool
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
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
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct MeetReadout: View {
    let caption: String
    let numeral: String
    let unit: String?
    let beneath: String
    let countsDown: Bool
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(spacing: 4) {
            Text(caption)
                .themeFont(.heading)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
            MeetNumeral(numeral: numeral, unit: unit, countsDown: countsDown)
            Text(beneath)
                .themeFont(.coachNote)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
}

/// The room between a stage's lift and its numeral. It stops growing, so the numeral holds its place
/// when a stage's controls change at the foot of the page.
struct MeetReadoutGap: View {
    var body: some View {
        Spacer(minLength: 8)
            .frame(maxHeight: 52)
    }
}

// MARK: - Waiting on an Attempt

private struct MeetOnDeckView: View {
    let deck: AttemptOnDeck
    let meet: Meet
    @Environment(MeetStore.self) private var store
    @Environment(\.themePalette) private var palette
    @State private var isChanging = false

    private var face: MeetOnDeckFace { MeetOnDeckFace(deck, rules: meet.rules) }

    var body: some View {
        let face = face
        MeetFullPage {
            VStack(spacing: Theme.cardSpacing) {
                MeetLiftHeader(lift: meet.lift(deck.lift))
                MeetReadoutGap()
                readout(face)
                Spacer(minLength: Theme.cardSpacing)
            }
        } foot: {
            VStack(spacing: 12) {
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
            VStack(spacing: 2) {
                if let instruction = face.instruction {
                    Text(instruction)
                        .themeFont(.heading)
                        .foregroundStyle(palette.textPrimary)
                        .accessibilityHidden(true)
                }
                if let detail = face.detail {
                    Text(detail)
                        .themeFont(.coachNote)
                        .foregroundStyle(palette.textSecondary)
                        .accessibilityHidden(true)
                }
                if let note = face.intervalNote {
                    Text(note)
                        .themeFont(.coachNote)
                        .foregroundStyle(palette.textSecondary)
                        .accessibilityIdentifier("meet-interval-note")
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
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
            if store.canUndo {
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
            Image(systemName: glyph(direction))
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
        .accessibilityShowsLargeContentViewer {
            Label(label, systemImage: glyph(direction))
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private func glyph(_ direction: WeightStepperButton.Direction) -> String {
        direction == .decrement ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill"
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
                    .meetAnswerCapsule(palette)
            }
            .buttonStyle(.pressScale)
            .accessibilityIdentifier("meet-mark-good")
            Button {
                mark(.noLift)
            } label: {
                Label("No lift", systemImage: "xmark")
                    .meetAnswerCapsule(palette)
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
            store.undo()
        } label: {
            Label("Undo", systemImage: "arrow.uturn.backward")
                .footPill(palette)
        }
        .buttonStyle(.pressScale)
        .accessibilityIdentifier("meet-undo")
    }
}

// MARK: - The day done

private struct MeetFinishedView: View {
    let meet: Meet
    @Environment(MeetStore.self) private var store
    @Environment(\.themePalette) private var palette

    var body: some View {
        MeetFullPage {
            VStack(spacing: Theme.sectionSpacing) {
                MeetReadoutGap()
                total
                VStack(spacing: Theme.cardSpacing) {
                    ForEach(meet.lifts.filter { !$0.attempts.isEmpty }, id: \.lift) { lift in
                        MeetLiftHeader(lift: lift)
                    }
                }
                Spacer(minLength: 0)
            }
        } foot: {
            if store.canUndo {
                MeetUndoPill()
            }
        }
    }

    @ViewBuilder
    private var total: some View {
        VStack(spacing: 6) {
            if let total = meet.total {
                title("Total")
                MeetNumeral(numeral: total.numeral, unit: "kg", countsDown: false)
                Text(total.poundsLabel)
                    .themeFont(.coachNote)
                    .foregroundStyle(palette.textSecondary)
            } else {
                title("No total")
                Text("A lift with no good attempt leaves no total.")
                    .themeFont(.coachNote)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("meet-total")
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .themeFont(.ceremonyTitle)
            .foregroundStyle(palette.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}
