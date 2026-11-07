import SwiftUI

struct MeetPlanView: View {
    @Environment(MeetStore.self) private var store
    @Environment(\.themePalette) private var palette
    @State private var editing: MeetPlanEditing?
    @State private var areRulesShown = false
    @State private var isDeleteAsked = false

    var body: some View {
        Group {
            if let meet = store.meet {
                plan(meet)
            } else {
                empty
            }
        }
        .background {
            palette.paperBackground
                .overlay { palette.lighting.pageSunbeam?.gradientView }
                .ignoresSafeArea()
        }
        .navigationTitle("Meet")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var empty: some View {
        VStack(spacing: 16) {
            Text("No Meet planned")
                .themeFont(.sheetTitle)
                .foregroundStyle(palette.textPrimary)
            Text("Enter the day and your coach's Attempts. The app counts you through the warm-up room and each Attempt Window.")
                .themeFont(.coachNote)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                let today = MeetDate(containing: store.now(), in: .current)
                store.start(Meet(date: today, federation: .ipf))
            } label: {
                Text("Plan a Meet")
                    .logCapsuleMetrics()
                    .foregroundStyle(palette.actionText)
                    .background(palette.actionFill, in: .capsule)
            }
            .buttonStyle(.pressScale)
            .accessibilityIdentifier("meet-plan-start")
        }
        .padding(Theme.pageMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func plan(_ meet: Meet) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Theme.sectionSpacing) {
                    dateAndFederation(meet)
                    ForEach(meet.lifts, id: \.lift) { lift in
                        MeetLiftSection(lift: lift, rules: meet.rules) { editing = $0 }
                    }
                    flight(meet)
                    footRow(meet)
                }
                .padding(Theme.pageMargin)
            }
            .scrollDismissesKeyboard(.interactively)
            .meetScrollFade()
            if meet.stage(at: store.now()) != .noAttempts {
                platformButton
            }
        }
        .sheet(item: $editing) { editing in
            sheet(editing, meet: meet)
        }
        .sheet(isPresented: $areRulesShown) {
            MeetRulesSheet(federation: meet.federation)
        }
    }

    private func dateAndFederation(_ meet: Meet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(meet.date.countdownLabel(from: store.now(), in: .current))
                    .themeFont(.statsValue)
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityIdentifier("meet-countdown")
                Spacer(minLength: 8)
                DatePicker(
                    "Meet date",
                    selection: Binding {
                        meet.date.noon(in: .current)
                    } set: { picked in
                        store.edit { $0.date = MeetDate(containing: picked, in: .current) }
                    },
                    displayedComponents: .date
                )
                .labelsHidden()
                .accessibilityIdentifier("meet-date")
            }
            Picker(
                "Federation",
                selection: Binding {
                    meet.federation
                } set: { federation in
                    store.edit { $0.federation = federation }
                }
            ) {
                ForEach(Federation.allCases, id: \.self) { federation in
                    Text(federation.name).tag(federation)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("meet-federation")
        }
    }

    private func flight(_ meet: Meet) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MeetCountRow(
                label: "Lifters in Flight",
                value: Binding {
                    meet.liftersInFlight
                } set: { count in
                    store.edit { $0.liftersInFlight = count }
                },
                identifier: "meet-lifters"
            )
            MeetCountRow(
                label: "Seconds per Attempt",
                value: Binding {
                    meet.secondsPerAttempt
                } set: { seconds in
                    store.edit { $0.secondsPerAttempt = seconds }
                },
                identifier: "meet-seconds-per-attempt"
            )
            Text("Your estimates.")
                .themeFont(.coachNote)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footRow(_ meet: Meet) -> some View {
        HStack(spacing: 10) {
            Button {
                areRulesShown = true
            } label: {
                Text("\(meet.federation.name) rules")
                    .footPill(palette)
            }
            .buttonStyle(.pressScale)
            .accessibilityIdentifier("meet-rules")
            Button {
                isDeleteAsked = true
            } label: {
                MeetGlyphPill(systemName: "trash")
            }
            .buttonStyle(.pressScale)
            .accessibilityLabel("Delete this Meet")
            .accessibilityIdentifier("meet-delete")
            // On the trash itself, so the popover's arrow points at what it asks about.
            .confirmationDialog("Delete this Meet?", isPresented: $isDeleteAsked, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { store.delete() }
            } message: {
                Text("Its Attempts and Warm-up Room Plans are erased from this phone. Your Sheet never held them.")
            }
        }
    }

    private var platformButton: some View {
        NavigationLink {
            MeetPlatformView()
        } label: {
            Text("To the Platform")
                .logCapsuleMetrics()
                .foregroundStyle(palette.actionText)
                .background(palette.actionFill, in: .capsule)
        }
        .buttonStyle(.pressScale)
        .padding(.horizontal, Theme.pageMargin)
        .padding(.vertical, 8)
        .accessibilityIdentifier("meet-to-platform")
    }

    @ViewBuilder
    private func sheet(_ editing: MeetPlanEditing, meet: Meet) -> some View {
        switch editing {
        case .attempt(let lift, let ordinal):
            attemptSheet(meet.lift(lift), ordinal: ordinal, rules: meet.rules)
        case .newStep(let lift):
            newStepSheet(meet.lift(lift), rules: meet.rules)
        case .step(let lift, let step):
            MeetWarmupStepSheet(
                title: "\(lift.name) warm-up",
                step: step,
                rules: meet.rules,
                onDelete: {
                    store.edit { $0.editLift(lift) { $0.setWarmupRoomPlan($0.warmupRoomPlan.filter { $0 != step }) } }
                },
                onSave: { edited in
                    store.edit { $0.editLift(lift) { $0.setWarmupRoomPlan($0.warmupRoomPlan.filter { $0 != step } + [edited]) } }
                }
            )
        }
    }

    private func newStepSheet(_ lift: MeetLift, rules: FederationRules) -> some View {
        let last = lift.warmupRoomPlan.last
        let start = WarmupRoomStep(
            kilograms: last?.kilograms ?? WarmupRoomPlanFill.bar,
            reps: last?.reps ?? 5,
            attemptsOut: max(1, (last?.attemptsOut ?? 21) - 3)
        )
        return MeetWarmupStepSheet(title: "\(lift.lift.name) warm-up", step: start, rules: rules, onDelete: nil) { step in
            store.edit { $0.editLift(lift.lift) { $0.setWarmupRoomPlan($0.warmupRoomPlan + [step]) } }
        }
    }

    private func attemptSheet(_ lift: MeetLift, ordinal: AttemptOrdinal, rules: FederationRules) -> some View {
        let existing = lift.attempts.indices.contains(ordinal.rawValue) ? lift.attempts[ordinal.rawValue] : nil
        let before = ordinal.rawValue > 0 ? lift.attempts[ordinal.rawValue - 1].kilograms : nil
        return MeetWeightSheet(
            title: "\(lift.lift.name) \(ordinal.name.lowercased())",
            entry: MeetWeightEntry(called: existing?.kilograms, after: before, rules: rules),
            saveLabel: "Save",
            idleLabel: "Save",
            unchanged: nil,
            terms: nil,
            onClear: existing == nil ? nil : { store.edit { $0.editLift(lift.lift) { $0.clear(from: ordinal) } } },
            onSave: { weight in
                store.edit { $0.editLift(lift.lift) { $0.enter(weight, at: ordinal) } }
            }
        )
    }
}
