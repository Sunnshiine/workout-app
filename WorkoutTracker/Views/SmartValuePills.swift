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
    let dismissFieldUIRequest: Int

    @State private var form: SmartValuePillsForm
    @State private var editingPill: FocusedPill?
    @State private var showsRPEGrid = false
    @State private var showsLoggedCheckmark = false
    @Environment(\.themePalette) private var palette
    @FocusState private var focusedPill: FocusedPill?

    init(
        set: ExerciseSet,
        previousSetWeight: Double?,
        trainingMax: Double?,
        onLog: @escaping (SetLog) -> Void,
        onSkip: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        dismissFieldUIRequest: Int = 0,
        showsLoggedCheckmarkInitially: Bool = false
    ) {
        self.set = set
        self.onLog = onLog
        self.onSkip = onSkip
        self.onDelete = onDelete
        self.dismissFieldUIRequest = dismissFieldUIRequest
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
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: dismissFieldUI)
        }
        .onChange(of: dismissFieldUIRequest) { _, _ in
            dismissFieldUI()
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
        let textColor = isPlaceholder ? Color.secondary : palette.valueText
        let strokeColor = isInvalid ? Color.red : palette.pillStroke
        let strokeWidth = isInvalid ? 2.0 : 1.0

        return VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if editingPill == pill {
                TextField(display, text: text)
                    .keyboardType(keyboardType)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(palette.valueText)
                    .focused($focusedPill, equals: pill)
            } else {
                Text(display)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(textColor)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Theme.pillMinHeight, alignment: .leading)
        .padding(.horizontal, 12)
        .background(palette.pillFill, in: .rect(cornerRadius: Theme.pillCornerRadius))
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
        let strokeColor = isInvalid ? Color.red : palette.pillStroke
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
                    .foregroundStyle(palette.valueText)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.pillMinHeight, alignment: .leading)
            .padding(.horizontal, 12)
            .background(palette.pillFill, in: .rect(cornerRadius: Theme.pillCornerRadius))
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
        .foregroundStyle(palette.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.pillFill, in: .capsule)
        .overlay(Capsule().strokeBorder(palette.pillStroke, lineWidth: 1))
    }

    private var actionControls: some View {
        VStack(spacing: 8) {
            HoldToSkipLogButton(
                logTitle: form.logButtonTitle,
                canLog: form.canLog,
                showsLoggedCheckmark: showsLoggedCheckmark,
                onLogTap: submitLog,
                onSkip: onSkip,
                onPressStarted: dismissFieldUI
            )

            if set.state != .pending {
                HStack {
                    Spacer()

                    Menu {
                        Button("Clear", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .imageScale(.large)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }

    private func submitLog() {
        guard let log = form.submitLog() else { return }
        withAnimation(Theme.logButtonCheckmarkAnimation) {
            showsLoggedCheckmark = true
        }
        onLog(log)
    }

    private func dismissFieldUI() {
        editingPill = nil
        focusedPill = nil
        showsRPEGrid = false
    }

    private func formField(for pill: FocusedPill) -> SmartValuePillsForm.Field {
        switch pill {
        case .weight: .weight
        case .reps: .reps
        }
    }

}

private struct HoldToSkipLogButton: View {
    let logTitle: String
    let canLog: Bool
    let showsLoggedCheckmark: Bool
    let onLogTap: () -> Void
    let onSkip: () -> Void
    let onPressStarted: () -> Void

    @State private var skipProgress = 0.0
    @State private var skipPressStartedAt: Date?
    @State private var skipCompleted = false
    @State private var suppressNextLogTap = false
    @State private var skipRevealTask: Task<Void, Never>?
    @State private var skipTask: Task<Void, Never>?
    @State private var suppressLogTapTask: Task<Void, Never>?
    @Environment(\.themePalette) private var palette

    var body: some View {
        Button {
            guard !suppressNextLogTap else {
                suppressNextLogTap = false
                return
            }
            onLogTap()
        } label: {
            buttonContent
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .onLongPressGesture(
            minimumDuration: policy.holdDuration,
            maximumDistance: 44,
            pressing: { isPressing in
                if isPressing {
                    startSkipHoldIfNeeded()
                } else {
                    finishSkipHold()
                }
            },
            perform: completeSkip
        )
        .font(.headline.weight(.bold))
        .foregroundStyle(logForegroundStyle)
        .padding(.vertical, 14)
        .background {
            ZStack(alignment: .leading) {
                logBackgroundStyle
                Color.red.opacity(0.86)
                    .scaleEffect(x: skipProgress, y: 1, anchor: .leading)
            }
            .clipShape(.rect(cornerRadius: Theme.pillCornerRadius))
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                .strokeBorder(logStrokeStyle, lineWidth: logStrokeWidth)
        )
        .opacity(presentation.controlOpacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityValue(skipProgress > 0 ? "\(Int((skipProgress * 100).rounded()))% Skip" : "")
        .accessibilityHint(presentation.accessibilityHint)
        .accessibilityIdentifier("log-active-set-button")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Skip") {
            completeSkip()
        }
    }

    private var buttonContent: some View {
        ZStack {
            HStack(spacing: 8) {
                if showsLoggedCheckmark {
                    Image(systemName: "checkmark")
                        .font(.headline.weight(.bold))
                        .transition(.scale.combined(with: .opacity))
                }

                Text(logTitle)
            }
            .opacity(presentation.logOpacity)

            if presentation.showsSkipAffordance {
                HStack {
                    Spacer()

                    Label("Skip", systemImage: "forward.end.fill")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.86), in: .capsule)
                }
                .padding(.horizontal, 10)
            }

            Text("Skipped")
                .opacity(presentation.skipOpacity)
        }
        .frame(maxWidth: .infinity)
    }

    private var presentation: HoldToSkipButtonPresentation {
        HoldToSkipButtonPresentation(progress: skipProgress, logTitle: logTitle, canLog: canLog)
    }

    private var logBackgroundStyle: Color {
        palette.accent
    }

    private var logForegroundStyle: Color {
        palette.accentDarkText
    }

    private var logStrokeStyle: Color {
        .clear
    }

    private var logStrokeWidth: CGFloat {
        0
    }

    private var policy: HoldToSkipPolicy {
        HoldToSkipPolicy()
    }

    private func startSkipHoldIfNeeded() {
        guard skipPressStartedAt == nil else { return }
        onPressStarted()
        skipPressStartedAt = Date()
        skipCompleted = false
        skipProgress = 0
        skipRevealTask?.cancel()
        skipTask?.cancel()
        skipRevealTask = Task { @MainActor in
            try? await Task.sleep(for: .nanoseconds(Int64((policy.revealDelay * 1_000_000_000).rounded())))
            let elapsed = skipPressStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            guard !Task.isCancelled, policy.shouldRevealProgress(elapsed: elapsed), !skipCompleted else { return }
            withAnimation(.linear(duration: policy.progressAnimationDuration)) {
                skipProgress = 1
            }
        }
        skipTask = Task { @MainActor in
            try? await Task.sleep(for: .nanoseconds(Int64((policy.holdDuration * 1_000_000_000).rounded())))
            guard !Task.isCancelled else { return }
            completeSkip()
        }
    }

    private func finishSkipHold() {
        let elapsed = skipPressStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let outcome = policy.releaseOutcome(elapsed: elapsed, skipCompleted: skipCompleted)
        skipRevealTask?.cancel()
        skipRevealTask = nil
        skipTask?.cancel()
        skipTask = nil
        skipPressStartedAt = nil

        switch outcome {
        case .log:
            resetSkipProgress()
            onLogTap()
            suppressLogTapOnce()
        case .cancelSkip:
            resetSkipProgress()
            suppressLogTapOnce()
        case .skip:
            completeSkip()
        case .ignore:
            suppressLogTapOnce()
        }
    }

    private func completeSkip() {
        guard !skipCompleted else { return }
        suppressLogTapOnce()
        skipCompleted = true
        skipRevealTask?.cancel()
        skipRevealTask = nil
        skipTask?.cancel()
        skipTask = nil
        onSkip()
    }

    private func suppressLogTapOnce() {
        suppressNextLogTap = true
        suppressLogTapTask?.cancel()
        suppressLogTapTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            suppressNextLogTap = false
            suppressLogTapTask = nil
        }
    }

    private func resetSkipProgress() {
        withAnimation(.easeOut(duration: Theme.logButtonCheckmarkDuration)) {
            skipProgress = 0
        }
    }
}

extension Double {
    fileprivate var weightLabel: String {
        rounded() == self ? String(Int(self)) : String(self)
    }
}
