import SwiftUI
import UIKit

#if canImport(CoreHaptics)
    import CoreHaptics
#endif

/// The Active Set Card's input block (DESIGN.md §5.2, pick input-block3-c): weight
/// leads as the card's biggest number flanked by round ± steppers; Reps and RPE are
/// side-by-side one-tap scroll rails; a true Log capsule previews the exact Set Log.
struct SmartValuePills: View {
    let set: ExerciseSet
    let mode: SetCardMode
    let onLog: (SetLog) -> Void
    let onSkip: () -> Void
    let onDelete: () -> Void
    let inputDismissalRequestID: Int

    @State private var form: SmartValuePillsForm
    @State private var isEditingWeight = false
    @State private var showsLoggedCheckmark = false
    @Environment(\.themePalette) private var palette
    @FocusState private var weightFieldFocused: Bool

    init(
        set: ExerciseSet,
        mode: SetCardMode = .logging,
        previousSetWeight: Double?,
        trainingMax: Double?,
        onLog: @escaping (SetLog) -> Void,
        onSkip: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        showsLoggedCheckmarkInitially: Bool = false,
        inputDismissalRequestID: Int = 0
    ) {
        self.set = set
        self.mode = mode
        self.onLog = onLog
        self.onSkip = onSkip
        self.onDelete = onDelete
        self.inputDismissalRequestID = inputDismissalRequestID
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
        VStack(spacing: Theme.inputBlockSpacing) {
            weightControl

            HStack(alignment: .top, spacing: 12) {
                ValueRail(
                    chips: repsPresentation.chips,
                    selectedIndex: repsPresentation.selectedIndex,
                    label: "Reps",
                    isInvalid: form.invalidFields.contains(.reps),
                    onSelect: { form.repsText = $0 }
                )

                ValueRail(
                    chips: rpePresentation.railChips,
                    selectedIndex: rpePresentation.selectedIndex,
                    label: "RPE",
                    isInvalid: form.invalidFields.contains(.rpe),
                    onSelect: { form.rpeText = $0 }
                )
            }

            if presentation.showsLogControls {
                actionControls
            } else if form.hasChanges, form.changedValidLog == nil {
                Text("Complete weight, reps, and RPE to update this logged set.")
                    .font(Theme.font(.fieldLabel))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .task(id: isEditingWeight) {
            weightFieldFocused = isEditingWeight
        }
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: dismissFieldUI)
        }
        .onChange(of: inputDismissalRequestID) { _, _ in
            dismissFieldUI()
        }
        .onDisappear(perform: commitChangedDraftIfNeeded)
    }

    private var presentation: SetCardPresentation {
        SetCardPresentation(mode: mode, set: set)
    }

    private var repsPresentation: RepsScalePresentation {
        RepsScalePresentation(prescribedReps: set.prescribedReps, selection: form.repsText)
    }

    private var rpePresentation: RPEScalePresentation {
        RPEScalePresentation(prescribedRPE: form.prescribedRPE, selection: form.rpeText)
    }

    // MARK: - Weight (the card's biggest number)

    private var weightControl: some View {
        HStack(spacing: 12) {
            weightStepper(.decrement, id: "weight-decrement")

            weightValue
                .frame(maxWidth: .infinity)

            weightStepper(.increment, id: "weight-increment")
        }
        .accessibilityElement(children: .contain)
    }

    /// Validation marks only the offending field with `danger` (DESIGN.md §5.2): an invalid weight
    /// tints its own number, leaving reps/RPE untouched.
    private var weightForeground: Color {
        form.invalidFields.contains(.weight) ? palette.danger : palette.textPrimary
    }

    @ViewBuilder
    private var weightValue: some View {
        if isEditingWeight {
            TextField(form.weightDisplay, text: $form.weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(Theme.font(.weightEntry))
                .foregroundStyle(weightForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .focused($weightFieldFocused)
                // The decimal pad carries no return key, so give the athlete a discoverable way out
                // of the field when they open it and choose not to enter a weight — dismissing the
                // keyboard without logging (the background/header taps are the same escape, less
                // obvious). Semantic-only, so no haptic here.
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done", action: dismissFieldUI)
                            .accessibilityIdentifier("weight-keyboard-done")
                    }
                }
                .accessibilityIdentifier("weight-pill")
        } else {
            Text(form.weightDisplay)
                .font(Theme.font(.weightEntry))
                .foregroundStyle(weightForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
                .onTapGesture { isEditingWeight = true }
                .accessibilityLabel("Weight, \(form.weightDisplay)")
                .accessibilityIdentifier("weight-pill")
                .accessibilityAddTraits(.isButton)
        }
    }

    @ViewBuilder
    private func weightStepper(_ direction: WeightStepperButton.Direction, id: String) -> some View {
        if form.allowsWeightStepping {
            WeightStepperButton(direction: direction, accessibilityIdentifier: id) {
                stepWeight(direction)
            }
        } else {
            // Hold the slot so the number stays centered even when stepping is disabled (bodyweight).
            Color.clear.frame(width: Theme.weightStepperDiameter, height: Theme.weightStepperDiameter)
        }
    }

    private func stepWeight(_ direction: WeightStepperButton.Direction) {
        // The form owns the clamp; the View only answers with the matching haptic —
        // the dud at the floor, the detent tick on a normal step.
        let hitFloor = form.stepWeight(direction == .increment ? .up : .down)
        InputHapticPlayer.shared.play(hitFloor ? Theme.Haptics.skipDud : Theme.Haptics.stepperTick)
    }

    // MARK: - Log capsule / skip

    private var actionControls: some View {
        VStack(spacing: 8) {
            HoldToSkipLogButton(
                logTitle: form.logButtonTitle,
                canLog: form.canLog,
                isSkipped: set.state == .skipped,
                showsLoggedCheckmark: showsLoggedCheckmark,
                onLogTap: submitLog,
                onSkip: skip,
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
                            .foregroundStyle(palette.textSecondary)
                    }
                    .accessibilityIdentifier("clear-logged-set-menu")
                }
            }
        }
    }

    /// Reviewing an already-logged Set commits silently: any changed, valid draft is written when
    /// the card leaves the screen (collapse or navigation), with the header's Saved label as feedback.
    private func commitChangedDraftIfNeeded() {
        guard presentation.commitsChangesOnDisappear, let log = form.changedValidLog else { return }
        onLog(log)
    }

    private func submitLog() {
        guard let log = form.submitLog() else { return }
        InputHapticPlayer.shared.play(Theme.Haptics.logTap)
        withAnimation(Theme.logButtonCheckmarkAnimation) {
            showsLoggedCheckmark = true
        }
        onLog(log)
    }

    private func skip() {
        InputHapticPlayer.shared.play(Theme.Haptics.skipDud)
        onSkip()
    }

    private func dismissFieldUI() {
        isEditingWeight = false
        weightFieldFocused = false
    }
}

// MARK: - Value rail (Reps / RPE)

/// A scroll rail (DESIGN.md §5.2): 48×44 cells inside a `rail`-radius track, the selected value a
/// cream chip with an inset action ring, its prescription tick below. The strip is offset-driven —
/// tapping a visible cell re-centers it, and a horizontal drag slides through the values one detent
/// at a time — so the selected value renders centered in offscreen snapshots (which never apply
/// async scrolling; ledger salvage note 1).
private struct ValueRail: View {
    let chips: [ValueRailChip]
    let selectedIndex: Int
    let label: String
    var isInvalid = false
    let onSelect: (String) -> Void
    @State private var dragAnchorIndex: Int?
    /// A drag is in flight (or just ended this event turn). It gates the cell buttons: as the strip
    /// re-centers on the dragged value, the lifted finger sits over a *different* cell, and that
    /// cell's button firing on release would override the drag — snapping the value back to where the
    /// finger landed (the reported "release jumps back to the original number"). The flag clears one
    /// runloop turn after the drag ends, after the synchronous release has been suppressed.
    @State private var isDragging = false
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let offset = ValueRailLayout.contentOffset(
                    trackWidth: geo.size.width,
                    cellWidth: Theme.railCellWidth,
                    spacing: 0,
                    selectedIndex: selectedIndex
                )

                HStack(spacing: 0) {
                    ForEach(chips) { chip in
                        cell(chip)
                    }
                }
                .frame(height: geo.size.height)
                .offset(x: offset)
                .animation(.snappy(duration: 0.22), value: selectedIndex)
            }
            .frame(height: Theme.railTrackHeight)
            .background(palette.railFill, in: .rect(cornerRadius: Theme.Radius.rail))
            .clipShape(.rect(cornerRadius: Theme.Radius.rail))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.rail)
                    .strokeBorder(isInvalid ? palette.danger : .clear, lineWidth: 2)
            }
            .overlay(alignment: .leading) { edgeFade(leading: true) }
            .overlay(alignment: .trailing) { edgeFade(leading: false) }
            .simultaneousGesture(dragToSelect)

            Text(label)
                .font(Theme.font(.fieldLabel))
                .foregroundStyle(palette.textSecondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    /// Sliding the rail follows the finger detent by detent: each cell-width of horizontal travel
    /// moves the selection one value from where the drag began, with the detent tick on each move.
    /// Simultaneous with the cell buttons so taps keep working unchanged.
    private var dragToSelect: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                isDragging = true
                let anchor = dragAnchorIndex ?? selectedIndex
                dragAnchorIndex = anchor
                let target = ValueRailLayout.draggedIndex(
                    anchorIndex: anchor,
                    translation: value.translation.width,
                    cellWidth: Theme.railCellWidth,
                    spacing: 0,
                    count: chips.count
                )
                guard target != selectedIndex, chips.indices.contains(target) else { return }
                onSelect(chips[target].label)
                InputHapticPlayer.shared.play(Theme.Haptics.railDetentTick)
            }
            .onEnded { _ in
                dragAnchorIndex = nil
                // Clear on the next runloop turn so the release's cell-button tap — dispatched in
                // this same event turn — still sees `isDragging` and is suppressed.
                DispatchQueue.main.async { isDragging = false }
            }
    }

    private func cell(_ chip: ValueRailChip) -> some View {
        Button {
            // A tap that was actually the tail of a drag must not re-select the cell under the
            // lifted finger — the drag's selection is authoritative (see `isDragging`).
            guard !isDragging else { return }
            onSelect(chip.label)
            InputHapticPlayer.shared.play(Theme.Haptics.railDetentTick)
        } label: {
            Text(chip.label)
                .font(Theme.font(.railChipValue))
                .foregroundStyle(chip.isSelected ? palette.textPrimary : palette.textSecondary)
                .frame(width: Theme.railCellWidth, height: Theme.railCellHeight)
                .background {
                    if chip.isSelected {
                        RoundedRectangle(cornerRadius: Theme.Radius.cell)
                            .fill(palette.railSelectedFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.cell)
                                    .strokeBorder(palette.action, lineWidth: 2)
                            )
                            .padding(Theme.railCellInset)
                    }
                }
                .overlay(alignment: .bottom) {
                    if chip.isPrescribed {
                        Capsule()
                            .fill(palette.prescriptionTick)
                            .frame(width: Theme.prescriptionTickWidth, height: Theme.prescriptionTickHeight)
                            .padding(.bottom, Theme.railCellInset + 3)
                            .accessibilityHidden(true)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(chip.accessibilityIdentifier)
        .accessibilityLabel("\(label) \(chip.label)")
        .accessibilityAddTraits(chip.isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func edgeFade(leading: Bool) -> some View {
        LinearGradient(
            colors: leading
                ? [palette.railFill, palette.railFill.opacity(0)]
                : [palette.railFill.opacity(0), palette.railFill],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: Theme.railEdgeFadeWidth)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Weight ± stepper

/// A ~54pt round stepper flanking the weight value. Its ± is a drawn glyph, not an SF Symbol, so
/// the control carries no inline font (token sheet §4 choke point) and the thin round-cap strokes
/// match pick input-block3-c.
struct WeightStepperButton: View {
    enum Direction: Equatable { case decrement, increment }

    let direction: Direction
    let accessibilityIdentifier: String
    let action: () -> Void
    @Environment(\.themePalette) private var palette

    var body: some View {
        Button(action: action) {
            StepperGlyph(direction: direction)
                .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .foregroundStyle(palette.action)
                .frame(width: 22, height: 22)
                .frame(width: Theme.weightStepperDiameter, height: Theme.weightStepperDiameter)
                .background(palette.pillFill, in: .circle)
                .overlay(Circle().strokeBorder(palette.pillStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(direction == .decrement ? "Decrease weight" : "Increase weight")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct StepperGlyph: Shape {
    let direction: WeightStepperButton.Direction

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        if direction == .increment {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        return path
    }
}

// MARK: - Log capsule

/// The Log capsule (DESIGN.md §5.3): a true capsule with `logShadow`, previewing the exact Set Log.
/// Hold-to-skip fills with the muted `skipFillOverlay` — never danger red, no icon badge — and the
/// skipped state is a transparent capsule with muted text on a 1.5px dashed empty bed.
private struct HoldToSkipLogButton: View {
    let logTitle: String
    let canLog: Bool
    let isSkipped: Bool
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
        Group {
            if isSkipped {
                skippedBed
            } else {
                logButtonSurface
            }
        }
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
        .contentShape(.rect)
        .onTapGesture(perform: logTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityValue(skipProgress > 0 ? "\(Int((skipProgress * 100).rounded()))% Skip" : "")
        .accessibilityHint(presentation.accessibilityHint)
        .accessibilityIdentifier("log-active-set-button")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            logTap()
        }
        .accessibilityAction(named: "Skip") {
            completeSkip()
        }
    }

    private var logButtonSurface: some View {
        buttonContent
            .font(Theme.font(.logCapsule))
            .foregroundStyle(logForegroundStyle)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background {
                ZStack(alignment: .leading) {
                    logBackgroundStyle
                    (palette.skipFillOverlay ?? palette.skipStroke)
                        .scaleEffect(x: skipProgress, y: 1, anchor: .leading)
                }
                .clipShape(.capsule)
            }
            .overlay {
                if case .incomplete = presentation.tone {
                    Capsule().strokeBorder(palette.pillStroke, lineWidth: 1)
                }
            }
            .themeElevation(logShadow, in: Capsule())
    }

    /// The dashed "empty bed" the skipped state settles into (§5.3): transparent, muted text.
    private var skippedBed: some View {
        Text("Skipped")
            .font(Theme.font(.logCapsule))
            .foregroundStyle(palette.textSecondary)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .overlay {
                Capsule()
                    .strokeBorder(palette.skipStroke, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
    }

    private var buttonContent: some View {
        ZStack {
            HStack(spacing: 8) {
                if showsLoggedCheckmark {
                    Image(systemName: "checkmark")
                        .transition(.scale.combined(with: .opacity))
                }

                Text(logTitle)
            }
            .opacity(presentation.logOpacity)

            Text("Skipped")
                .opacity(presentation.skipOpacity)
        }
        .frame(maxWidth: .infinity)
    }

    private var presentation: HoldToSkipButtonPresentation {
        HoldToSkipButtonPresentation(progress: skipProgress, logTitle: logTitle, canLog: canLog)
    }

    /// The green drop / green light only rides the primary (loggable) capsule.
    private var logShadow: [Theme.BoxShadow] {
        presentation.tone == .primary ? palette.logShadow : []
    }

    private var logBackgroundStyle: Color {
        switch presentation.tone {
        case .primary: palette.action
        case .incomplete: palette.pillFill
        }
    }

    private var logForegroundStyle: Color {
        switch presentation.tone {
        case .primary: palette.actionText
        case .incomplete: palette.textPrimary
        }
    }

    private var policy: HoldToSkipPolicy {
        HoldToSkipPolicy()
    }

    private func logTap() {
        guard !suppressNextLogTap else {
            suppressNextLogTap = false
            return
        }
        onLogTap()
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
        case .deferToTap:
            resetSkipProgress()
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

// MARK: - Input haptics

/// The Crisp input haptics (token sheet §7, ledger §2.9): rail detent ticks, stepper ± ticks with
/// the floor dud, the firm log tap, the skip dud. Semantic-only — never on form fields or chrome.
@MainActor
final class InputHapticPlayer {
    static let shared = InputHapticPlayer()

    #if canImport(CoreHaptics)
        private var engine: CHHapticEngine?

        func play(_ tuning: Theme.HapticTuning) {
            guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
            do {
                let engine = try activeEngine()
                let event = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(tuning.intensity)),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(tuning.sharpness)),
                    ],
                    relativeTime: 0
                )
                let pattern = try CHHapticPattern(events: [event], parameters: [])
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: 0)
            } catch {
                engine = nil
            }
        }

        private func activeEngine() throws -> CHHapticEngine {
            if let engine { return engine }
            let engine = try CHHapticEngine()
            try engine.start()
            self.engine = engine
            return engine
        }
    #else
        func play(_: Theme.HapticTuning) {}
    #endif
}
