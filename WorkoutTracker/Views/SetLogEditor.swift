import SwiftUI
import UIKit

struct SetLogEditor: View {
    let set: ExerciseSet
    let onLog: (SetLog) -> Void
    let onSkip: () -> Void
    let onDelete: () -> Void

    @State private var weightText: String
    @State private var repsText: String
    @State private var rpeText: String

    init(
        set: ExerciseSet,
        onLog: @escaping (SetLog) -> Void,
        onSkip: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.set = set
        self.onLog = onLog
        self.onSkip = onSkip
        self.onDelete = onDelete
        let log = set.setLog
        _weightText = State(initialValue: log?.weight.label ?? (set.prescribedLoad == "BW" ? "BW" : ""))
        _repsText = State(initialValue: log.map { String($0.reps) } ?? "")
        _rpeText = State(
            initialValue: log.map { $0.rpe.rounded() == $0.rpe ? String(Int($0.rpe)) : String($0.rpe) } ?? ""
        )
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            editorRow

            VStack(alignment: .leading, spacing: 8) {
                inputFields
                actionControls
            }
        }
        .font(.callout)
    }

    private var editorRow: some View {
        HStack(spacing: 8) {
            inputFields
            actionControls
        }
    }

    private var inputFields: some View {
        HStack(spacing: 8) {
            logTextField("Wt", text: $weightText, keyboardType: .decimalPad)
            logTextField("Reps", text: $repsText, keyboardType: .numberPad)
            logTextField("RPE", text: $rpeText, keyboardType: .decimalPad)
        }
    }

    private var actionControls: some View {
        HStack(spacing: 8) {
            Button("Log") {
                guard let log = makeLog() else { return }
                onLog(log)
            }
            .buttonStyle(.glassProminent)
            .disabled(makeLog() == nil)

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

    private func logTextField(
        _ title: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType
    ) -> some View {
        TextField(title, text: text)
            .keyboardType(keyboardType)
            .textFieldStyle(.roundedBorder)
            .frame(width: 70)
    }

    private func makeLog() -> SetLog? {
        SetLog(formatted: "\(weightText)x\(repsText)@\(rpeText)")
    }
}
