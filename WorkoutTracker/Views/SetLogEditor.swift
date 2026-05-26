import SwiftUI

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
        HStack(spacing: 8) {
            TextField("Wt", text: $weightText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
            TextField("Reps", text: $repsText)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
            TextField("RPE", text: $rpeText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)

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
        .font(.callout)
    }

    private func makeLog() -> SetLog? {
        SetLog(formatted: "\(weightText)x\(repsText)@\(rpeText)")
    }
}
