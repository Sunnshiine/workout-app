import SwiftUI
import UIKit

struct SmartValuePills: View {
    private enum FocusedPill {
        case weight
        case reps

        var accessibilityIdentifier: String {
            switch self {
            case .weight: "weight-pill"
            case .reps: "reps-pill"
            }
        }
    }

    let set: ExerciseSet
    let onLog: (SetLog) -> Void
    let onSkip: () -> Void
    let onDelete: () -> Void

    @State private var form: SmartValuePillsForm
    @State private var editingPill: FocusedPill?
    @State private var showsRPEGrid = false
    @State private var showsLoggedCheckmark = false
    @FocusState private var focusedPill: FocusedPill?

    init(
        set: ExerciseSet,
        previousSetWeight: Double?,
        trainingMax: Double?,
        onLog: @escaping (SetLog) -> Void,
        onSkip: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        showsLoggedCheckmarkInitially: Bool = false
    ) {
        self.set = set
        self.onLog = onLog
        self.onSkip = onSkip
        self.onDelete = onDelete
        _form = State(
            initialValue: SmartValuePillsForm(
                set: set,
                previousSetWeight: previousSetWeight,
                trainingMax: trainingMax
            )
        )
        _showsLoggedCheckmark = State(initialValue: showsLoggedCheckmarkInitially)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: Theme.pillSpacing) {
                valuePill(
                    label: "Weight",
                    display: form.weightDisplay,
                    text: $form.weightText,
                    pill: .weight,
                    keyboardType: .decimalPad
                )

                valuePill(
                    label: "Reps",
                    display: form.repsDisplay,
                    text: $form.repsText,
                    pill: .reps,
                    keyboardType: .numberPad
                )

                rpePill
            }

            if editingPill == .weight {
                incrementButtons
            }

            if showsRPEGrid {
                RPEGrid(
                    presentation: RPEGridPresentation(prescribedRPE: form.prescribedRPE),
                    selection: $form.rpeText,
                    isPresented: $showsRPEGrid
                )
            }

            actionControls
        }
        .task(id: editingPill) {
            focusedPill = editingPill
        }
    }

    private func valuePill(
        label: String,
        display: String,
        text: Binding<String>,
        pill: FocusedPill,
        keyboardType: UIKeyboardType
    ) -> some View {
        let field = formField(for: pill)
        let isInvalid = form.invalidFields.contains(field)
        let isPlaceholder = pill == .reps && form.isRepsDisplayingPlaceholder && editingPill != pill
        let textColor = isPlaceholder ? Color.secondary : Color.white
        let strokeColor = isInvalid ? Color.red : Theme.pillStroke
        let strokeWidth = isInvalid ? 2.0 : 1.0

        return VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if editingPill == pill {
                TextField(display, text: text)
                    .keyboardType(keyboardType)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .focused($focusedPill, equals: pill)
            } else {
                Text(display)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(textColor)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Theme.pillMinHeight, alignment: .leading)
        .padding(.horizontal, 12)
        .background(Theme.pillFill, in: .rect(cornerRadius: Theme.pillCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                .strokeBorder(strokeColor, lineWidth: strokeWidth)
        )
        .contentShape(.rect)
        .onTapGesture {
            showsRPEGrid = false
            editingPill = pill
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(display)")
        .accessibilityIdentifier(pill.accessibilityIdentifier)
        .accessibilityAddTraits(.isButton)
    }

    private var rpePill: some View {
        let isInvalid = form.invalidFields.contains(.rpe)
        let strokeColor = isInvalid ? Color.red : Theme.pillStroke
        let strokeWidth = isInvalid ? 2.0 : 1.0

        return Button {
            editingPill = nil
            focusedPill = nil
            showsRPEGrid.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("RPE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(form.rpeDisplay)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.pillMinHeight, alignment: .leading)
            .padding(.horizontal, 12)
            .background(Theme.pillFill, in: .rect(cornerRadius: Theme.pillCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                    .strokeBorder(strokeColor, lineWidth: strokeWidth)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rpe-pill")
    }

    private var incrementButtons: some View {
        HStack(spacing: 8) {
            ForEach(form.weightIncrementOptions, id: \.self) { increment in
                incrementButton("-\(increment.weightLabel)", by: -increment)
                incrementButton("+\(increment.weightLabel)", by: increment)
            }
        }
    }

    private func incrementButton(_ title: String, by increment: Double) -> some View {
        Button(title) {
            form.adjustWeight(by: increment)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.pillFill, in: .capsule)
        .overlay(Capsule().strokeBorder(Theme.pillStroke, lineWidth: 1))
    }

    private var actionControls: some View {
        VStack(spacing: 8) {
            Button {
                guard let log = form.submitLog() else { return }
                withAnimation(Theme.logButtonCheckmarkAnimation) {
                    showsLoggedCheckmark = true
                }
                onLog(log)
            } label: {
                HStack(spacing: 8) {
                    if showsLoggedCheckmark {
                        Image(systemName: "checkmark")
                            .font(.headline.weight(.bold))
                            .transition(.scale.combined(with: .opacity))
                    }

                    Text(form.logButtonTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .font(.headline.weight(.bold))
            .foregroundStyle(Theme.accentDarkText)
            .padding(.vertical, 14)
            .background(Theme.accent, in: .rect(cornerRadius: Theme.pillCornerRadius))
            .opacity(form.canLog ? 1 : 0.45)
            .accessibilityIdentifier("log-active-set-button")

            HStack {
                Button("Cancel") {
                    form.cancel()
                    editingPill = nil
                    focusedPill = nil
                    showsRPEGrid = false
                }
                .buttonStyle(.glass)

                Spacer()

                Menu {
                    Button("Skip", action: onSkip)
                    if set.state != .pending {
                        Button("Clear", role: .destructive, action: onDelete)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                }
                .buttonStyle(.glass)
            }
        }
    }

    private func formField(for pill: FocusedPill) -> SmartValuePillsForm.Field {
        switch pill {
        case .weight: .weight
        case .reps: .reps
        }
    }
}

extension Double {
    fileprivate var weightLabel: String {
        rounded() == self ? String(Int(self)) : String(self)
    }
}
