import SwiftUI

struct MeetAttemptWindowView: View {
    let window: AttemptWindow
    @Environment(MeetStore.self) private var store

    var body: some View {
        TimelineView(.periodic(from: window.startedAt, by: 1)) { _ in
            if let meet = store.meet, case .window(let open) = meet.stage(at: store.now()) {
                MeetAttemptWindowFaceView(
                    face: AttemptWindowFace(open),
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
    @FocusState private var isTyping: Bool

    init(face: AttemptWindowFace, open: OpenAttemptWindow, rules: FederationRules) {
        self.face = face
        self.open = open
        self.rules = rules
        _entry = State(initialValue: MeetWeightEntry(called: open.planned, after: open.marked, rules: rules))
    }

    private var previous: (kilograms: Kilograms, result: AttemptResult) { (open.marked, open.result) }

    var body: some View {
        MeetFullPage {
            VStack(spacing: Theme.cardSpacing) {
                if isTyping {
                    rule
                } else {
                    MeetLiftHeader(lift: store.meet?.lift(open.lift) ?? .empty(open.lift), nameRole: .exerciseName)
                    MeetReadoutGap()
                    readout
                }
                Spacer(minLength: 0)
                // Above the stepper, so a note arriving under a thumb that is stepping moves nothing.
                VStack(spacing: 8) {
                    MeetWeightNoteView(note: entry.note(after: previous))
                    MeetWeightStepper(
                        entry: $entry,
                        isTyping: $isTyping,
                        label: face.attemptLabel,
                        spokenLabel: "\(face.attemptLabel) in kilograms"
                    )
                }
            }
        } foot: {
            actions
        }
        .toolbar {
            // The page gives way to the keyboard, and the clock it was showing stays in reach of the eye.
            ToolbarItem(placement: .principal) {
                if isTyping {
                    Text(face.numeral)
                        .themeFont(.statsValue)
                        .foregroundStyle(face.stage == .expired ? palette.textSecondary : palette.textPrimary)
                        .accessibilityLabel(face.markLine)
                        .accessibilityValue(face.accessibilityValue)
                        .accessibilityIdentifier("meet-window")
                }
            }
        }
        .onChange(of: face.stage) { _, stage in
            feel(stage)
        }
    }

    private var readout: some View {
        VStack(spacing: 10) {
            MeetReadout(
                caption: face.caption,
                numeral: face.numeral,
                unit: nil,
                beneath: face.markLine,
                countsDown: true,
                numeralInk: face.stage == .expired ? palette.textSecondary : palette.textPrimary
            )
            rule
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(face.markLine)
        .accessibilityValue(face.accessibilityValue)
        .accessibilityIdentifier("meet-window")
    }

    /// The room stays held, so the numeral above does not move when the rule arrives.
    private var rule: some View {
        Text(face.rule)
            .themeFont(.heading)
            .foregroundStyle(palette.textPrimary)
            .multilineTextAlignment(.center)
            .opacity(face.showsRule ? 1 : 0)
            .animation(.easeOut(duration: Theme.Motion.crossfade), value: face.showsRule)
            .accessibilityHidden(!face.showsRule)
            .accessibilityIdentifier("meet-window-rule")
    }

    private var actions: some View {
        VStack(spacing: 12) {
            // The question's room stays held and the answers take Submit's frame, so the page holds
            // still when the clock runs out.
            Text("What did the table enter?")
                .themeFont(.heading)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
                .opacity(face.stage == .expired ? 1 : 0)
                .accessibilityHidden(face.stage != .expired)
                .accessibilityIdentifier("meet-table-question")
            ZStack {
                if face.stage == .expired {
                    expiredAnswers
                        .transition(.opacity)
                } else {
                    submitButton
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: Theme.Motion.crossfade), value: face.stage)
            .meetSettles(on: face.stage)
            MeetFootChips {
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

    /// The phone cannot see a card reach the table, so it asks, and neither answer stands out. The
    /// first is what the rule says, the second what the stepper holds.
    private var expiredAnswers: some View {
        HStack(spacing: 12) {
            Button {
                HapticPlayer.shared.play(.input(Theme.Haptics.logTap))
                try? store.acceptTableEntry()
            } label: {
                Text(open.tableEntry.label)
                    .meetAnswerCapsule(palette)
            }
            .buttonStyle(.pressScale)
            .accessibilityLabel("The table entered \(open.tableEntry.spoken)")
            .accessibilityIdentifier("meet-accept-table-entry")
            if let handedIn = entry.kilograms, handedIn != open.tableEntry, entry.canSave(after: previous) {
                Button {
                    submit()
                } label: {
                    Text(handedIn.label)
                        .meetAnswerCapsule(palette)
                }
                .buttonStyle(.pressScale)
                .accessibilityLabel("I handed in \(handedIn.spoken)")
                .accessibilityIdentifier("meet-handed-in")
            }
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
