import SwiftUI

enum MeetPlanEditing: Identifiable {
    case attempt(MainLift, AttemptOrdinal)
    case newStep(MainLift)
    case step(MainLift, WarmupRoomStep)

    var id: String {
        switch self {
        case .attempt(let lift, let ordinal): "attempt-\(lift.rawValue)-\(ordinal.rawValue)"
        case .newStep(let lift): "new-step-\(lift.rawValue)"
        case .step(let lift, let step): "step-\(lift.rawValue)-\(step.attemptsOut)-\(step.kilograms.hundredths)-\(step.reps)"
        }
    }
}

struct MeetLiftSection: View {
    let lift: MeetLift
    let rules: FederationRules
    let onEdit: (MeetPlanEditing) -> Void
    @Environment(MeetStore.self) private var store
    @Environment(\.themePalette) private var palette
    @FocusState private var isTypingRack: Bool

    private static let cellPadding: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(lift.lift.name)
                .themeFont(.heading)
                .foregroundStyle(palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            attemptColumns
            if lift.lift != .deadlift {
                rackField
            }
            warmups
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attemptColumns: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(AttemptOrdinal.allCases, id: \.self) { ordinal in
                attemptColumn(ordinal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func attemptColumn(_ ordinal: AttemptOrdinal) -> some View {
        let identifier = "meet-attempt-\(lift.lift.rawValue)-\(ordinal.name.lowercased())"
        if lift.attempts.indices.contains(ordinal.rawValue) {
            let attempt = lift.attempts[ordinal.rawValue]
            Button {
                onEdit(.attempt(lift.lift, ordinal))
            } label: {
                attemptLabel(ordinal, attempt: attempt)
            }
            .buttonStyle(.pressScale)
            .disabled(attempt.isMarked)
            .accessibilityLabel("\(lift.lift.name) \(ordinal.name.lowercased())")
            .accessibilityValue("\(attempt.kilograms.spoken), \(attempt.kilograms.poundsLabel), \(attempt.state.spoken)")
            .accessibilityIdentifier(identifier)
        } else if ordinal.rawValue == lift.attempts.count {
            Button {
                onEdit(.attempt(lift.lift, ordinal))
            } label: {
                blankLabel(ordinal)
            }
            .buttonStyle(.pressScale)
            .accessibilityLabel("Enter \(lift.lift.name) \(ordinal.name.lowercased())")
            .accessibilityIdentifier(identifier)
        } else {
            Color.clear
        }
    }

    /// A fill says this can still be changed, so a marked Attempt goes without one.
    private func attemptLabel(_ ordinal: AttemptOrdinal, attempt: Attempt) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Text(ordinal.name)
                    .themeFont(.fieldLabel)
                    .foregroundStyle(palette.textSecondary)
                if let glyph = attempt.state.markGlyph {
                    Image(systemName: glyph)
                        .themeFont(.fieldLabel)
                        .foregroundStyle(attempt.state == .good ? palette.action : palette.textSecondary)
                }
            }
            Text(attempt.kilograms.numeral)
                .themeFont(.statsValue)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            Text(attempt.kilograms.poundsLabel)
                .themeFont(.runlineSecondary)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(Self.cellPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(attempt.isMarked ? .clear : palette.railFill, in: .rect(cornerRadius: Theme.Radius.cell))
        .contentShape(.rect)
    }

    /// Only the next Attempt is an empty bed. One that cannot be entered yet does not exist.
    private func blankLabel(_ ordinal: AttemptOrdinal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ordinal.name)
                .themeFont(.fieldLabel)
                .foregroundStyle(palette.textSecondary)
            Image(systemName: "plus")
                .themeFont(.runline)
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .padding(Self.cellPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.cell)
                .strokeBorder(
                    palette.tileGhostStroke,
                    style: StrokeStyle(lineWidth: Theme.blockTileGhostStroke, dash: [Theme.blockTileGhostDash])
                )
        }
        .contentShape(.rect)
    }

    private var rackField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Rack Height")
                .themeFont(.fieldLabel)
                .foregroundStyle(palette.textSecondary)
            TextField(
                "Rack Height",
                text: Binding {
                    lift.rackHeights
                } set: { text in
                    // A wrapping field's return key types a line break, so it ends the typing instead.
                    if text.contains("\n") { isTypingRack = false }
                    store.edit { $0.editLift(lift.lift) { $0.rackHeights = text.replacingOccurrences(of: "\n", with: "") } }
                },
                prompt: Text("From your weigh-in").foregroundStyle(palette.textSecondary),
                axis: .vertical
            )
            .themeFont(.coachNote)
            .foregroundStyle(palette.textPrimary)
            .lineLimit(1...4)
            .submitLabel(.done)
            .focused($isTypingRack)
            .accessibilityLabel("\(lift.lift.name) Rack Height")
            .accessibilityIdentifier("meet-rack-\(lift.lift.rawValue)")
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(palette.pillFill, in: .rect(cornerRadius: Theme.Radius.cell))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.cell)
                    .strokeBorder(palette.pillStroke, lineWidth: 1)
            }
            .contentShape(.rect)
            .onTapGesture { isTypingRack = true }
        }
    }

    private var warmups: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Warm-up Room Plan")
                Spacer(minLength: 8)
                if !lift.warmupRoomPlan.isEmpty {
                    Text("Attempts Out")
                }
            }
            .themeFont(.fieldLabel)
            .foregroundStyle(palette.textSecondary)
            ForEach(lift.warmupRoomPlan, id: \.self) { step in
                Button {
                    onEdit(.step(lift.lift, step))
                } label: {
                    stepRow(step)
                }
                .buttonStyle(.pressScale)
                .accessibilityLabel(step.spoken)
                .accessibilityIdentifier("meet-step-\(lift.lift.rawValue)-\(step.attemptsOut)")
            }
            HStack(spacing: 10) {
                if lift.warmupRoomPlan.isEmpty, let opener = lift.attempts.first {
                    fillButton(opener: opener.kilograms)
                }
                Button {
                    onEdit(.newStep(lift.lift))
                } label: {
                    Image(systemName: "plus")
                        .footPill(palette)
                }
                .buttonStyle(.pressScale)
                .accessibilityLabel("Add a warm-up step")
                .accessibilityIdentifier("meet-add-step-\(lift.lift.rawValue)")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func fillButton(opener: Kilograms) -> some View {
        Button {
            let steps = WarmupRoomPlanFill.evenSteps(toOpener: opener, barMultiple: rules.barMultiple.value)
            store.edit { $0.editLift(lift.lift) { $0.setWarmupRoomPlan(steps) } }
        } label: {
            Text("Even steps to \(opener.label)")
                .footPill(palette)
        }
        .buttonStyle(.pressScale)
        .accessibilityHint("Fills steps from the empty bar to the opener, which you can change")
        .accessibilityIdentifier("meet-fill-\(lift.lift.rawValue)")
    }

    private func stepRow(_ step: WarmupRoomStep) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(step.kilograms.label)
                .themeFont(.setNumber)
                .foregroundStyle(palette.textPrimary)
            Text("× \(step.reps)")
                .themeFont(.setOf)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 8)
            Text("\(step.attemptsOut)")
                .themeFont(.setOf)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, Self.cellPadding)
        .frame(minHeight: 44)
        .background(palette.railFill, in: .rect(cornerRadius: Theme.Radius.cell))
        .contentShape(.rect)
    }
}

extension AttemptState {
    /// The mark as a glyph, because the Greenhouse has no hue for a good or a bad lift.
    var markGlyph: String? {
        switch self {
        case .planned, .submitted: nil
        case .good: "checkmark"
        case .noLift: "xmark"
        }
    }
}
