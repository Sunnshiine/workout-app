import SwiftUI
import UIKit

struct LoggedSetReviewCard: View {
    let set: ExerciseSet
    let setOrdinal: Int
    let setCount: Int
    let showsSavedConfirmation: Bool
    let onCommit: (SetLog) -> Void
    let onCollapse: () -> Void

    @State private var form: SmartValuePillsForm
    @State private var showsRPEGrid = false
    @State private var editingField: LoggedSetReviewEditableField?
    @Environment(\.sessionAllClearRevision) private var sessionAllClearRevision
    @Environment(\.themePalette) private var palette
    @FocusState private var focusedField: LoggedSetReviewEditableField?

    private var presentation: LoggedSetReviewPresentation {
        LoggedSetReviewPresentation(set: set)
    }

    init(
        set: ExerciseSet,
        setOrdinal: Int,
        setCount: Int,
        showsSavedConfirmation: Bool,
        onCommit: @escaping (SetLog) -> Void,
        onCollapse: @escaping () -> Void
    ) {
        self.set = set
        self.setOrdinal = setOrdinal
        self.setCount = setCount
        self.showsSavedConfirmation = showsSavedConfirmation
        self.onCommit = onCommit
        self.onCollapse = onCollapse
        _form = State(
            initialValue: SmartValuePillsForm(
                set: set,
                previousSetWeight: nil,
                trainingMax: nil
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.accent)
                        .textCase(.uppercase)

                    Text("Set \(setOrdinal) of \(setCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if showsSavedConfirmation {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.accent)
                }

                Button(action: onCollapse) {
                    Image(systemName: "chevron.up")
                        .font(.callout.weight(.semibold))
                        .accessibilityLabel("Collapse logged set")
                }
                .buttonStyle(.glass)
            }

            if presentation.allowsEditing {
                if let referenceText = presentation.referenceText {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Original Unstructured Set Log")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(referenceText)
                            .font(.callout.weight(.semibold))
                    }
                }
                editableFields
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(presentation.detailText)
                        .font(.headline.weight(.semibold))
                    Text([set.prescribedReps, set.prescribedLoad].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if form.hasChanges, form.changedValidLog == nil {
                Text("Complete weight, reps, and RPE to update this logged set.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(palette.activeCardFill, in: .rect(cornerRadius: Theme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .strokeBorder(palette.activeCardStroke.opacity(0.8), lineWidth: 1)
        )
        .onDisappear(perform: commitValidDraft)
        .task(id: editingField) {
            focusedField = editingField
        }
        .onChange(of: focusedField) { _, newValue in
            editingField = newValue
        }
        .onChange(of: sessionAllClearRevision) { _, _ in
            dismissFieldUI()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("logged-set-review-card")
    }

    private var editableFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: Theme.pillSpacing) {
                valueField(
                    label: "Weight",
                    display: form.weightDisplay,
                    text: $form.weightText,
                    field: .weight,
                    keyboardType: .decimalPad
                )

                valueField(
                    label: "Reps",
                    display: form.repsDisplay,
                    text: $form.repsText,
                    field: .reps,
                    keyboardType: .numberPad
                )

                Button {
                    focusedField = nil
                    editingField = nil
                    showsRPEGrid.toggle()
                } label: {
                    fieldLabel(label: "RPE", display: form.rpeDisplay, field: .rpe)
                }
                .buttonStyle(.plain)
                .contentShape(.rect)
                .accessibilityIdentifier(LoggedSetReviewEditableField.rpe.accessibilityIdentifier)
            }

            if showsRPEGrid {
                RPEGrid(
                    presentation: RPEGridPresentation(prescribedRPE: form.prescribedRPE),
                    selection: $form.rpeText,
                    isPresented: $showsRPEGrid
                )
            }
        }
    }

    private func valueField(
        label: String,
        display: String,
        text: Binding<String>,
        field: LoggedSetReviewEditableField,
        keyboardType: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if editingField == field {
                TextField(display, text: text)
                    .keyboardType(keyboardType)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(palette.valueText)
                    .focused($focusedField, equals: field)
            } else {
                Text(display)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(palette.valueText)
            }
        }
        .modifier(LoggedReviewPillChrome(isFocused: editingField == field))
        .contentShape(.rect)
        .onTapGesture { focus(field, from: .padding) }
        .accessibilityLabel("\(label), \(display)")
        .accessibilityIdentifier(field.accessibilityIdentifier)
        .accessibilityAddTraits(.isButton)
    }

    private func fieldLabel(label: String, display: String, field: LoggedSetReviewEditableField) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(display)
                .font(.title3.weight(.bold))
                .foregroundStyle(palette.valueText)
        }
        .modifier(LoggedReviewPillChrome(isFocused: showsRPEGrid))
        .accessibilityIdentifier(field.accessibilityIdentifier)
    }

    private func focus(_ field: LoggedSetReviewEditableField, from region: LoggedSetReviewPillHitRegion) {
        let target = field.editTarget(for: region)
        showsRPEGrid = false
        editingField = target
        focusedField = target
    }

    private func dismissFieldUI() {
        editingField = nil
        focusedField = nil
    }

    private func commitValidDraft() {
        guard let log = form.changedValidLog else { return }
        onCommit(log)
    }
}

private struct LoggedReviewPillChrome: ViewModifier {
    let isFocused: Bool
    @Environment(\.themePalette) private var palette

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, minHeight: Theme.pillMinHeight, alignment: .leading)
            .padding(.horizontal, 12)
            .background(palette.pillFill, in: .rect(cornerRadius: Theme.pillCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                    .strokeBorder(isFocused ? palette.accent : palette.pillStroke, lineWidth: isFocused ? 2 : 1)
            )
    }
}
