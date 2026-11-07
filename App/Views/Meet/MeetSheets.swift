import SwiftUI

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
