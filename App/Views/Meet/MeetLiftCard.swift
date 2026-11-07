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

struct MeetLiftCard: View {
    let lift: MeetLift
    let rules: FederationRules
    let onEdit: (MeetPlanEditing) -> Void
    @Environment(MeetStore.self) private var store
    @Environment(\.themePalette) private var palette
    @FocusState private var isTypingRack: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(lift.lift.meetName)
                .themeFont(.heading)
                .foregroundStyle(palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            attemptColumns
            if lift.lift != .deadlift {
                rackField
            }
            warmups
        }
        .padding(Theme.cardSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: .rect(cornerRadius: Theme.Radius.card))
        .themeElevation(palette.surfaceShadow, in: .rect(cornerRadius: Theme.Radius.card))
    }

    private var attemptColumns: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(AttemptOrdinal.allCases, id: \.self) { ordinal in
                attemptColumn(ordinal)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
            .accessibilityLabel("\(lift.lift.meetName) \(ordinal.name.lowercased())")
            .accessibilityValue("\(attempt.kilograms.spoken), \(attempt.kilograms.poundsLabel), \(attempt.state.spoken)")
            .accessibilityIdentifier(identifier)
        } else if ordinal.rawValue == lift.attempts.count {
            Button {
                onEdit(.attempt(lift.lift, ordinal))
            } label: {
                blankLabel(ordinal, isNext: true)
            }
            .buttonStyle(.pressScale)
            .accessibilityLabel("Enter \(lift.lift.meetName) \(ordinal.name.lowercased())")
            .accessibilityIdentifier(identifier)
        } else {
            blankLabel(ordinal, isNext: false)
                .accessibilityHidden(true)
        }
    }

    private func attemptLabel(_ ordinal: AttemptOrdinal, attempt: Attempt) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ordinal.name)
                .themeFont(.fieldLabel)
                .foregroundStyle(palette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(attempt.kilograms.numeral)
                    .themeFont(.statsValue)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("kg")
                    .themeFont(.runlineSecondary)
                    .foregroundStyle(palette.textSecondary)
                if let glyph = attempt.state.markGlyph {
                    Image(systemName: glyph)
                        .themeFont(.runline)
                        .foregroundStyle(attempt.state == .good ? palette.action : palette.textSecondary)
                }
            }
            Text(attempt.kilograms.poundsLabel)
                .themeFont(.runlineSecondary)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(.rect)
    }

    private func blankLabel(_ ordinal: AttemptOrdinal, isNext: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ordinal.name)
                .themeFont(.fieldLabel)
                .foregroundStyle(palette.textSecondary)
            RoundedRectangle(cornerRadius: Theme.Radius.cell)
                .strokeBorder(palette.skipStroke, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .overlay {
                    if isNext {
                        Image(systemName: "plus")
                            .themeFont(.runline)
                            .foregroundStyle(palette.textPrimary)
                    }
                }
                .frame(height: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    private var rackField: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Rack")
                .themeFont(.fieldLabel)
                .foregroundStyle(palette.textSecondary)
            TextField(
                lift.lift == .squat ? "14, racks in" : "8, safety 4, blocks",
                text: Binding {
                    lift.rackHeights
                } set: { text in
                    // A wrapping field's return key types a line break, so it ends the typing instead.
                    if text.contains("\n") { isTypingRack = false }
                    store.edit { $0.editLift(lift.lift) { $0.rackHeights = text.replacingOccurrences(of: "\n", with: "") } }
                },
                axis: .vertical
            )
            .themeFont(.coachNote)
            .foregroundStyle(palette.textPrimary)
            .lineLimit(1...4)
            .submitLabel(.done)
            .focused($isTypingRack)
            .accessibilityLabel("\(lift.lift.meetName) rack height")
            .accessibilityIdentifier("meet-rack-\(lift.lift.rawValue)")
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(.rect)
        .onTapGesture { isTypingRack = true }
    }

    private var warmups: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Warm-up room")
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
            Text(step.kilograms.numeral)
                .themeFont(.setNumber)
                .foregroundStyle(palette.textPrimary)
            Text("× \(step.reps)")
                .themeFont(.setOf)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 8)
            Text("\(step.attemptsOut) out")
                .themeFont(.runlineSecondary)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(minHeight: 44)
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
