import SwiftUI

struct MeetAttemptStrip: View {
    let lift: MeetLift
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(lift.attempts.enumerated()), id: \.offset) { index, attempt in
                // Room for a mark in every gap at every type size, so a mark landing moves no numeral.
                if index > 0 {
                    Image(systemName: "checkmark")
                        .hidden()
                }
                Text(attempt.kilograms.numeral)
                    .foregroundStyle(attempt.state == .planned ? palette.textSecondary : palette.textPrimary)
                    .overlay(alignment: .leading) {
                        if let glyph = attempt.state.markGlyph {
                            Image(systemName: glyph)
                                .foregroundStyle(attempt.state == .good ? palette.action : palette.textSecondary)
                                .frame(width: 0, alignment: .trailing)
                                .offset(x: -3)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(AttemptOrdinal(rawValue: index)?.name ?? ""), \(attempt.kilograms.spoken), \(attempt.state.spoken)"
                    )
            }
        }
        .themeFont(.runline)
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
    let nameRole: Theme.TypeRole
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(spacing: 4) {
            Text(lift.lift.name)
                .themeFont(nameRole)
                .multilineTextAlignment(.center)
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

    /// The widest the page allows and taller than any other control, for a chalky thumb that does
    /// not look.
    func meetPad(_ palette: Theme.Palette) -> some View {
        frame(maxWidth: .infinity, minHeight: 88)
            .background(palette.pillFill, in: .capsule)
            .themeElevation(palette.lighting.raisedControlShadow, in: Capsule())
            .contentShape(Capsule())
    }

    /// Scrolled content fades out inside the page's edges and never passes under a bar or a control,
    /// so nothing ghosts behind the title or a capsule. A page at rest keeps its margin clear of the fade.
    func meetScrollFade() -> some View {
        scrollEdgeEffectHidden(true)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: Theme.pageMargin)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: Theme.pageMargin)
                }
            }
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
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    content
                        .padding(Theme.pageMargin)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                .meetScrollFade()
            }
            foot
                .padding(.horizontal, Theme.pageMargin)
                .padding(.bottom, 8)
        }
    }
}

/// Undo keeps one frame at the page's left edge on every stage, for a thumb that is not looking, and
/// the row holds its room so the controls above it stay put when Undo comes and goes.
struct MeetFootChips<Trailing: View>: View {
    @ViewBuilder let trailing: Trailing
    @Environment(MeetStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            if store.canUndo {
                MeetUndoPill()
            }
            Spacer(minLength: 0)
            trailing
        }
        .frame(minHeight: 44)
    }
}

/// A question that takes the pounds line's place. Its room stays held, so the numeral holds still
/// when it is asked.
struct MeetWeightQuestion {
    let text: String
    let isAsked: Bool
}

/// The numeral is a field, so a record Attempt's half kilo can be typed.
struct MeetWeightStepper: View {
    @Binding var entry: MeetWeightEntry
    @FocusState.Binding var isTyping: Bool
    let label: String
    let spokenLabel: String
    let question: MeetWeightQuestion?
    @Environment(\.themePalette) private var palette
    @State private var selection: TextSelection?

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .themeFont(.fieldLabel)
                .foregroundStyle(palette.textSecondary)
                // The selection's handle stands above the field's top edge.
                .padding(.bottom, isTyping ? 10 : 0)
            HStack(spacing: 16) {
                WeightStepperButton(direction: .decrement, accessibilityIdentifier: "meet-weight-down") { step { $0.stepDown() } }
                TextField(
                    "Kilograms",
                    text: $entry.text,
                    selection: $selection,
                    prompt: Text(verbatim: "0").foregroundStyle(palette.textSecondary)
                )
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
            ZStack {
                Text(entry.pounds)
                    .themeFont(.runlineSecondary)
                    .foregroundStyle(palette.textSecondary)
                    .opacity(poundsGiveWay ? 0 : 1)
                    .accessibilityHidden(poundsGiveWay)
                    .accessibilityIdentifier("meet-weight-pounds")
                if let question {
                    Text(question.text)
                        .themeFont(.heading)
                        .foregroundStyle(palette.textPrimary)
                        .multilineTextAlignment(.center)
                        .opacity(question.isAsked ? 1 : 0)
                        .accessibilityHidden(!question.isAsked)
                        .accessibilityIdentifier("meet-weight-question")
                }
            }
        }
        .onChange(of: isTyping) { _, isTyping in
            // The first digit replaces the weight, not the front of it, while the clock runs.
            if isTyping { selection = TextSelection(range: entry.text.startIndex..<entry.text.endIndex) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done", systemImage: "checkmark") { isTyping = false }
            }
        }
    }

    private var poundsGiveWay: Bool {
        guard let question else { return false }
        return question.isAsked
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
    /// The weight the save would leave as it is, so the capsule stays neutral until the number moves.
    let unchanged: Kilograms?
    let onClear: (() -> Void)?
    let onSave: (Kilograms) -> Void
    @State private var entry: MeetWeightEntry
    @FocusState private var isTyping: Bool
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        entry: MeetWeightEntry,
        saveLabel: String,
        unchanged: Kilograms?,
        onClear: (() -> Void)?,
        onSave: @escaping (Kilograms) -> Void
    ) {
        self.title = title
        self.saveLabel = saveLabel
        self.unchanged = unchanged
        self.onClear = onClear
        self.onSave = onSave
        _entry = State(initialValue: entry)
    }

    private var canSave: Bool { entry.canSave(after: nil) && entry.kilograms != unchanged }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.cardSpacing) {
                Text(title)
                    .themeFont(.sheetTitle)
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)
                MeetWeightStepper(
                    entry: $entry,
                    isTyping: $isTyping,
                    label: "Kilograms",
                    spokenLabel: "Kilograms",
                    question: nil
                )
                MeetWeightNoteView(note: entry.note(after: nil))
                Spacer(minLength: 0)
                Button {
                    guard let weight = entry.kilograms else { return }
                    onSave(weight)
                    dismiss()
                } label: {
                    MeetCapsuleLabel(
                        text: entry.kilograms.map { "\(saveLabel) \($0.label)" } ?? saveLabel,
                        canAct: canSave
                    )
                }
                .buttonStyle(.pressScale)
                .disabled(!canSave)
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
        // A blank weight wants a number, so the keyboard comes up.
        .onAppear { isTyping = entry.text.isEmpty }
    }
}

struct MeetWarmupStepSheet: View {
    let title: String
    let onDelete: (() -> Void)?
    let onSave: (WarmupRoomStep) -> Void
    @State private var entry: MeetWeightEntry
    @State private var reps: Int
    @State private var attemptsOut: Int
    @FocusState private var isTyping: Bool
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

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
        _entry = State(initialValue: MeetWeightEntry(called: step.kilograms, after: nil, rules: rules))
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
                    MeetWeightStepper(
                        entry: $entry,
                        isTyping: $isTyping,
                        label: "Kilograms",
                        spokenLabel: "Kilograms",
                        question: nil
                    )
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
        // Larger type grows the page past the medium detent, which would cut the trash in half.
        .presentationDetents([typeSize > .large ? .fraction(0.6) : .medium, .large])
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
