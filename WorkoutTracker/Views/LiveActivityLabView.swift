import ActivityKit
import SwiftUI

struct LiveActivityLabView: View {
    @Environment(\.themePalette) private var palette
    @State private var controller = LiveActivityController()
    @State private var variant = LiveActivityLabDefaults.defaultVariant
    @State private var appearance = LiveActivityAppearance.dark
    @State private var setsDone = 3
    @State private var setsTotal = 5
    @State private var weight = 185
    @State private var restDurationSeconds = 90
    @State private var restStartDate = Date.now
    @State private var restEndDate = Date.now.addingTimeInterval(90)

    private let sessionLabel = "Week 2 - Day 3"
    private let exerciseName = "2-3:1:0 BB RDL"
    private let prescribedReps = "3-5"
    private let prescribedLoad = "RPE6"
    private let weightUnit = "lb"

    var body: some View {
        ZStack {
            palette.gradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.cardSpacing) {
                    statusSection
                    variantSection
                    appearanceSection
                    sampleStateSection
                    controlsSection
                }
                .padding()
            }
        }
        .navigationTitle("Live Activity Lab")
        .task {
            controller.refreshAuthorizationStatus()
        }
        .onChange(of: variant) { _, _ in
            updateIfActive()
        }
        .onChange(of: appearance) { _, _ in
            updateIfActive()
        }
        .onChange(of: setsDone) { _, _ in
            normalizeSets()
            updateIfActive()
        }
        .onChange(of: setsTotal) { _, _ in
            normalizeSets()
            updateIfActive()
        }
        .onChange(of: weight) { _, _ in
            updateIfActive()
        }
        .onChange(of: restDurationSeconds) { _, _ in
            restartRestTimer()
        }
    }

    private var statusSection: some View {
        LiveActivityLabSection(title: "Status") {
            Label(
                controller.areActivitiesEnabled ? "Live Activities enabled" : "Live Activities disabled",
                systemImage: controller.areActivitiesEnabled ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .font(Theme.font(.queuePill))
            .foregroundStyle(controller.areActivitiesEnabled ? palette.accent : Theme.danger)

            Text(controller.isActive ? "Prototype is running." : "Prototype is stopped.")
                .font(Theme.font(.queuePill))
                .foregroundStyle(.secondary)

            if let lastError = controller.lastError {
                Text(lastError)
                    .font(Theme.font(.historyChip))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var variantSection: some View {
        LiveActivityLabSection(title: "Prototype Variants") {
            LabField(label: "Production", value: LiveActivityLabDefaults.productionVariantTitle)
            LabField(label: "Prototype", value: variant.title)

            Picker("Prototype Variant", selection: $variant) {
                ForEach(LiveActivityLabDefaults.prototypeVariants) { variant in
                    Text(variant.title).tag(variant)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("live-activity-lab-variant-picker")
        }
    }

    private var appearanceSection: some View {
        LiveActivityLabSection(title: "Appearance") {
            Picker("Appearance", selection: $appearance) {
                ForEach(LiveActivityAppearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("live-activity-lab-appearance-picker")
        }
    }

    private var sampleStateSection: some View {
        LiveActivityLabSection(title: "Sample Workout State") {
            LabField(label: "Session", value: sessionLabel)
            LabField(label: "Exercise", value: exerciseName)
            LabField(label: "Reps", value: prescribedReps)
            LabField(label: "Load", value: prescribedLoad)

            Stepper(value: $setsDone, in: 0...setsTotal) {
                LabField(label: "Sets", value: "\(setsDone)/\(setsTotal)")
            }
            .accessibilityIdentifier("live-activity-lab-sets-done-stepper")

            Stepper(value: $setsTotal, in: 1...10) {
                LabField(label: "Total Sets", value: "\(setsTotal)")
            }
            .accessibilityIdentifier("live-activity-lab-sets-total-stepper")

            Stepper(value: $weight, in: 45...495, step: 5) {
                LabField(label: "Weight", value: "\(weight) \(weightUnit)")
            }
            .accessibilityIdentifier("live-activity-lab-weight-stepper")

            Stepper(value: $restDurationSeconds, in: 30...300, step: 15) {
                LabField(label: "Rest", value: restDurationLabel)
            }
            .accessibilityIdentifier("live-activity-lab-rest-duration-stepper")
        }
    }

    private var controlsSection: some View {
        LiveActivityLabSection(title: "Controls") {
            Button {
                startPrototype()
            } label: {
                Label("Start", systemImage: "play.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(!controller.areActivitiesEnabled)
            .accessibilityIdentifier("live-activity-lab-start-button")

            Button {
                Task { await controller.update(state: currentState) }
            } label: {
                Label("Update", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(!controller.isActive)
            .accessibilityIdentifier("live-activity-lab-update-button")

            Button {
                restartRestTimer()
            } label: {
                Label("Restart rest", systemImage: "timer")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("live-activity-lab-restart-rest-button")

            Button {
                logSet()
            } label: {
                Label("Log a set", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(!controller.isActive || setsDone >= setsTotal)
            .accessibilityIdentifier("live-activity-lab-log-set-button")

            Button(role: .destructive) {
                Task { await controller.end() }
            } label: {
                Label("End", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(!controller.isActive)
            .accessibilityIdentifier("live-activity-lab-end-button")
        }
    }

    private var currentState: WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            exerciseName: exerciseName,
            prescribedReps: prescribedReps,
            prescribedLoad: prescribedLoad,
            weightValue: "\(weight)",
            weightUnit: weightUnit,
            setsDone: setsDone,
            setsTotal: setsTotal,
            variant: variant,
            appearance: appearance,
            restStartDate: restStartDate,
            restEndDate: restEndDate
        )
    }

    private var restDurationLabel: String {
        let minutes = restDurationSeconds / 60
        let seconds = restDurationSeconds % 60
        guard minutes > 0 else { return "\(seconds)s" }
        return seconds == 0 ? "\(minutes)m" : "\(minutes)m \(seconds)s"
    }

    private func startPrototype() {
        let dates = freshRestDates()
        restStartDate = dates.start
        restEndDate = dates.end
        Task {
            await controller.start(
                state: makeState(restStartDate: dates.start, restEndDate: dates.end),
                sessionLabel: sessionLabel
            )
        }
    }

    private func restartRestTimer() {
        let dates = freshRestDates()
        restStartDate = dates.start
        restEndDate = dates.end
        guard controller.isActive else { return }

        Task {
            await controller.update(state: makeState(restStartDate: dates.start, restEndDate: dates.end))
        }
    }

    private func logSet() {
        setsDone = min(setsDone + 1, setsTotal)
        updateIfActive()
    }

    private func normalizeSets() {
        setsDone = min(max(setsDone, 0), setsTotal)
    }

    private func updateIfActive() {
        guard controller.isActive else { return }
        Task {
            await controller.update(state: currentState)
        }
    }

    private func freshRestDates() -> (start: Date, end: Date) {
        let start = Date.now
        return (start, start.addingTimeInterval(TimeInterval(restDurationSeconds)))
    }

    private func makeState(
        restStartDate: Date,
        restEndDate: Date
    ) -> WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            exerciseName: exerciseName,
            prescribedReps: prescribedReps,
            prescribedLoad: prescribedLoad,
            weightValue: "\(weight)",
            weightUnit: weightUnit,
            setsDone: setsDone,
            setsTotal: setsTotal,
            variant: variant,
            appearance: appearance,
            restStartDate: restStartDate,
            restEndDate: restEndDate
        )
    }
}

enum LiveActivityLabDefaults {
    static let defaultVariant = DesignVariant.restTimerSetsLeft
    static let productionVariantTitle = DesignVariant.restTimerSetsLeft.title
    static let prototypeVariants = DesignVariant.allCases
}

private struct LiveActivityLabSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Theme.font(.sheetTitle))

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(palette.surface, in: .rect(cornerRadius: Theme.Radius.card))
    }
}

private struct LabField: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(Theme.font(.queuePill))
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .font(Theme.font(.queuePill))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
