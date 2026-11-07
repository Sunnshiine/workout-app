import SwiftUI

struct MeetAttemptStrip: View {
    let lift: MeetLift
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(lift.attempts.enumerated()), id: \.offset) { index, attempt in
                HStack(spacing: 3) {
                    if let glyph = attempt.state.markGlyph {
                        Image(systemName: glyph)
                            .foregroundStyle(attempt.state == .good ? palette.action : palette.textSecondary)
                    }
                    Text(attempt.kilograms.numeral)
                        .foregroundStyle(attempt.state == .planned ? palette.textSecondary : palette.textPrimary)
                }
                .themeFont(.runline)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(AttemptOrdinal(rawValue: index)?.name ?? ""), \(attempt.kilograms.spoken), \(attempt.state.spoken)"
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("meet-attempt-strip-\(lift.lift.rawValue)")
    }
}

/// A capsule's label, green when it can act and neutral when it cannot, because a disabled button
/// keeps a custom label's colours.
struct MeetCapsuleLabel: View {
    let text: String
    let canAct: Bool
    @Environment(\.themePalette) private var palette

    var body: some View {
        Text(text)
            .logCapsuleMetrics()
            .foregroundStyle(canAct ? palette.actionText : palette.textSecondary)
            .background(canAct ? palette.actionFill : palette.pillFill, in: .capsule)
    }
}

struct MeetLiftHeader: View {
    let lift: MeetLift
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(spacing: 4) {
            Text(lift.lift.name)
                .themeFont(.heading)
                .foregroundStyle(palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            MeetAttemptStrip(lift: lift)
        }
    }
}

extension View {
    /// One of two answers the app cannot choose between, so neither is green.
    func meetAnswerCapsule(_ palette: Theme.Palette) -> some View {
        logCapsuleMetrics()
            .foregroundStyle(palette.textPrimary)
            .background(palette.pillFill, in: .capsule)
            .themeElevation(palette.lighting.raisedControlShadow, in: Capsule())
    }

    /// Holds off touches just after the controls under a thumb change, so the second tap of a double
    /// tap, or one tap too many on the count, cannot land on what replaced them.
    func meetSettles<Key: Equatable>(on key: Key) -> some View {
        modifier(MeetSettling(key: key))
    }
}

private struct MeetSettling<Key: Equatable>: ViewModifier {
    let key: Key
    @State private var isSettling = false

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!isSettling)
            .task(id: key) {
                isSettling = true
                try? await Task.sleep(for: .seconds(0.4))
                if !Task.isCancelled { isSettling = false }
            }
    }
}

/// A page that holds the whole screen and scrolls once large type outgrows it. Its foot stays in
/// reach of the thumb, above the keyboard, while the clock runs.
struct MeetFullPage<Content: View, Foot: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let foot: Foot

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .padding(Theme.pageMargin)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            foot
                .padding(.horizontal, Theme.pageMargin)
                .padding(.bottom, 8)
        }
    }
}

/// The numeral is a field, so a record attempt's half kilo can be typed.
struct MeetWeightStepper: View {
    @Binding var entry: MeetWeightEntry
    let label: String
    let spokenLabel: String
    @Environment(\.themePalette) private var palette
    @FocusState private var isTyping: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .themeFont(.fieldLabel)
                .foregroundStyle(palette.textSecondary)
            HStack(spacing: 16) {
                WeightStepperButton(direction: .decrement, accessibilityIdentifier: "meet-weight-down") { step { $0.stepDown() } }
                TextField("Kilograms", text: $entry.text, prompt: Text(verbatim: "0").foregroundStyle(palette.textSecondary))
                    .themeFont(.weightEntry)
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .minimumScaleFactor(0.5)
                    .focused($isTyping)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(spokenLabel)
                    .accessibilityIdentifier("meet-weight-field")
                WeightStepperButton(direction: .increment, accessibilityIdentifier: "meet-weight-up") { step { $0.stepUp() } }
            }
            Text(entry.pounds)
                .themeFont(.runlineSecondary)
                .foregroundStyle(palette.textSecondary)
                .accessibilityIdentifier("meet-weight-pounds")
        }
        // A blank weight has no number to step from, so the keyboard comes up.
        .onAppear { isTyping = entry.text.isEmpty }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done", systemImage: "checkmark") { isTyping = false }
            }
        }
    }

    private func step(_ change: (inout MeetWeightEntry) -> Void) {
        HapticPlayer.shared.play(.input(Theme.Haptics.stepperTick))
        isTyping = false
        change(&entry)
    }
}

struct MeetWeightNoteView: View {
    let note: MeetWeightNote?
    @Environment(\.themePalette) private var palette

    var body: some View {
        switch note {
        case .none:
            EmptyView()
        case .rule(let text):
            Text(text)
                .themeFont(.coachNote)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("meet-weight-note")
        case .refused(let text):
            DangerMarkedText(message: text, role: .coachNote)
                .accessibilityIdentifier("meet-weight-note")
        }
    }
}

struct MeetWeightSheet: View {
    let title: String
    let saveLabel: String
    let onClear: (() -> Void)?
    let onSave: (Kilograms) -> Void
    @State private var entry: MeetWeightEntry
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        entry: MeetWeightEntry,
        saveLabel: String,
        onClear: (() -> Void)?,
        onSave: @escaping (Kilograms) -> Void
    ) {
        self.title = title
        self.saveLabel = saveLabel
        self.onClear = onClear
        self.onSave = onSave
        _entry = State(initialValue: entry)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.cardSpacing) {
                Text(title)
                    .themeFont(.sheetTitle)
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)
                MeetWeightStepper(entry: $entry, label: "Kilograms", spokenLabel: "Kilograms")
                MeetWeightNoteView(note: entry.note(after: nil))
                Spacer(minLength: 0)
                Button {
                    guard let weight = entry.kilograms else { return }
                    onSave(weight)
                    dismiss()
                } label: {
                    MeetCapsuleLabel(
                        text: entry.kilograms.map { "\(saveLabel) \($0.label)" } ?? saveLabel,
                        canAct: entry.canSave(after: nil)
                    )
                }
                .buttonStyle(.pressScale)
                .disabled(!entry.canSave(after: nil))
                .accessibilityIdentifier("meet-weight-save")
                if let onClear {
                    Button {
                        onClear()
                        dismiss()
                    } label: {
                        Text("Clear")
                            .footPill(palette)
                    }
                    .buttonStyle(.pressScale)
                    .accessibilityIdentifier("meet-weight-clear")
                }
            }
            .padding(Theme.pageMargin)
            .background(palette.paperBackground.ignoresSafeArea())
        }
        .presentationDetents([.medium, .large])
    }
}

struct MeetWarmupStepSheet: View {
    let title: String
    let onDelete: (() -> Void)?
    let onSave: (WarmupRoomStep) -> Void
    @State private var entry: MeetWeightEntry
    @State private var reps: Int
    @State private var attemptsOut: Int
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        step: WarmupRoomStep,
        rules: FederationRules,
        onDelete: (() -> Void)?,
        onSave: @escaping (WarmupRoomStep) -> Void
    ) {
        self.title = title
        self.onDelete = onDelete
        self.onSave = onSave
        _entry = State(initialValue: MeetWeightEntry(step.kilograms, rules: rules))
        _reps = State(initialValue: step.reps)
        _attemptsOut = State(initialValue: step.attemptsOut)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.cardSpacing) {
                    Text(title)
                        .themeFont(.sheetTitle)
                        .foregroundStyle(palette.textPrimary)
                    MeetWeightStepper(entry: $entry, label: "Kilograms", spokenLabel: "Kilograms")
                    MeetWeightNoteView(note: entry.note(after: nil))
                    MeetCountRow(label: "Reps", value: $reps, identifier: "meet-step-reps")
                    MeetCountRow(label: "Attempts Out", value: $attemptsOut, identifier: "meet-step-attempts-out")
                    Button {
                        guard let weight = entry.kilograms else { return }
                        onSave(WarmupRoomStep(kilograms: weight, reps: reps, attemptsOut: attemptsOut))
                        dismiss()
                    } label: {
                        MeetCapsuleLabel(text: "Save", canAct: entry.canSave(after: nil))
                    }
                    .buttonStyle(.pressScale)
                    .disabled(!entry.canSave(after: nil))
                    .accessibilityIdentifier("meet-step-save")
                    if let onDelete {
                        Button {
                            onDelete()
                            dismiss()
                        } label: {
                            Image(systemName: "trash")
                                .footPill(palette)
                        }
                        .buttonStyle(.pressScale)
                        .accessibilityLabel("Delete this step")
                        .accessibilityIdentifier("meet-step-delete")
                    }
                }
                .padding(Theme.pageMargin)
            }
            .background(palette.paperBackground.ignoresSafeArea())
        }
        .presentationDetents([.large])
    }
}

struct MeetCountRow: View {
    let label: String
    @Binding var value: Int
    let identifier: String
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .themeFont(.heading)
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            WeightStepperButton(
                direction: .decrement,
                accessibilityLabel: "\(label), less",
                accessibilityIdentifier: "\(identifier)-down"
            ) {
                change(-1)
            }
            Text("\(value)")
                .themeFont(.setNumber)
                .foregroundStyle(palette.textPrimary)
                .frame(minWidth: 36)
                .accessibilityLabel(label)
                .accessibilityValue("\(value)")
                .accessibilityIdentifier(identifier)
            WeightStepperButton(
                direction: .increment,
                accessibilityLabel: "\(label), more",
                accessibilityIdentifier: "\(identifier)-up"
            ) {
                change(1)
            }
        }
    }

    private func change(_ amount: Int) {
        guard value + amount >= 1 else {
            HapticPlayer.shared.play(.input(Theme.Haptics.skipDud))
            return
        }
        HapticPlayer.shared.play(.input(Theme.Haptics.stepperTick))
        value += amount
    }
}

struct MeetRulesSheet: View {
    let federation: Federation
    @Environment(\.themePalette) private var palette

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.cardSpacing) {
                    Text("\(federation.name) rules")
                        .themeFont(.sheetTitle)
                        .foregroundStyle(palette.textPrimary)
                    ForEach(federation.rules.lines, id: \.text) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.text)
                                .themeFont(.coachNote)
                                .foregroundStyle(palette.textPrimary)
                            Text("Rule \(line.rule)")
                                .themeFont(.runlineSecondary)
                                .foregroundStyle(palette.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Text(federation.rules.rulebook)
                        .themeFont(.runlineSecondary)
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(Theme.pageMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(palette.paperBackground.ignoresSafeArea())
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("meet-rules-sheet")
    }
}
