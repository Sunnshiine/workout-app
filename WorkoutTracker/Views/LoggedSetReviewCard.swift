import SwiftUI
import UIKit

struct LoggedSetReviewCard: View {
    private enum FocusedField {
        case weight
        case reps
    }

    let set: ExerciseSet
    let setOrdinal: Int
    let setCount: Int
    let showsSavedConfirmation: Bool
    let onCommit: (SetLog) -> Void
    let onCollapse: () -> Void

    @State private var form: SmartValuePillsForm
    @State private var showsRPEGrid = false
    @FocusState private var focusedField: FocusedField?

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
                        .foregroundStyle(Theme.accent)
                        .textCase(.uppercase)

                    Text("Set \(setOrdinal) of \(setCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if showsSavedConfirmation {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
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
        .background(Theme.activeCardFill, in: .rect(cornerRadius: Theme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .strokeBorder(Theme.activeCardStroke.opacity(0.8), lineWidth: 1)
        )
        .onDisappear(perform: commitValidDraft)
        .accessibilityElement(children: .contain)
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
                    showsRPEGrid.toggle()
                } label: {
                    fieldLabel(label: "RPE", display: form.rpeDisplay)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("logged-rpe-pill")
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
        field: FocusedField,
        keyboardType: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField(display, text: text)
                .keyboardType(keyboardType)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .focused($focusedField, equals: field)
        }
        .frame(maxWidth: .infinity, minHeight: Theme.pillMinHeight, alignment: .leading)
        .padding(.horizontal, 12)
        .background(Theme.pillFill, in: .rect(cornerRadius: Theme.pillCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                .strokeBorder(Theme.pillStroke, lineWidth: 1)
        )
        .accessibilityLabel("\(label), \(display)")
    }

    private func fieldLabel(label: String, display: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(display)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, minHeight: Theme.pillMinHeight, alignment: .leading)
        .padding(.horizontal, 12)
        .background(Theme.pillFill, in: .rect(cornerRadius: Theme.pillCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                .strokeBorder(Theme.pillStroke, lineWidth: 1)
        )
    }

    private func commitValidDraft() {
        guard let log = form.changedValidLog else { return }
        onCommit(log)
    }
}
