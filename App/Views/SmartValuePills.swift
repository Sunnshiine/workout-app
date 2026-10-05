import SwiftUI
import UIKit

struct EditingWeightPreferenceKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// The Active Set Card's input block (DESIGN.md §5.2, pick input-block3-c): weight
/// leads as the card's biggest number flanked by round ± steppers; Reps and RPE are
/// side-by-side one-tap scroll rails; a true Log capsule previews the exact Set Log.
struct SmartValuePills: View {
    let set: ExerciseSet
    let mode: SetCardMode
    let suggestion: LoadSuggestion
    let onLog: (SetLog) -> Void
    let onSkip: () -> Void
    let onDelete: () -> Void
    let inputDismissalRequestID: Int

    @State private var form: SmartValuePillsForm
    @State private var isEditingWeight = false
    @State private var showsLoggedCheckmark = false
    @Environment(\.themePalette) private var palette
    @Environment(\.showsLoadBasis) private var showsLoadBasis
    @FocusState private var weightFieldFocused: Bool

    init(
        set: ExerciseSet,
        mode: SetCardMode = .logging,
        suggestion: LoadSuggestion,
        onLog: @escaping (SetLog) -> Void,
        onSkip: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        showsLoggedCheckmarkInitially: Bool = false,
        inputDismissalRequestID: Int = 0
    ) {
        self.set = set
        self.mode = mode
        self.suggestion = suggestion
        self.onLog = onLog
        self.onSkip = onSkip
        self.onDelete = onDelete
        self.inputDismissalRequestID = inputDismissalRequestID
        _form = State(initialValue: SmartValuePillsForm(set: set, suggestion: suggestion))
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
                    chips: rpePresentation.chips,
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
        // Focus can be taken away from outside this view (the stage-wide tap-to-dismiss
        // surface resigns the first responder directly); fold the edit UI when that happens
        // so the field doesn't linger unfocused.
        .onChange(of: weightFieldFocused) { _, focused in
            if !focused {
                isEditingWeight = false
            }
        }
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: dismissFieldUI)
        }
        .onChange(of: inputDismissalRequestID) { _, _ in
            dismissFieldUI()
        }
        .onChange(of: suggestion) { _, later in
            form.refreshPrefill(from: later, for: set)
        }
        .onDisappear(perform: commitChangedDraftIfNeeded)
        .preference(key: EditingWeightPreferenceKey.self, value: isEditingWeight)
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
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                weightStepper(.decrement, id: "weight-decrement")

                weightValue
                    .frame(maxWidth: .infinity)

                weightStepper(.increment, id: "weight-increment")
            }

            if showsLoadBasis, let loadBasisLine = form.loadBasisLine {
                if loadBasisLine.isShown {
                    loadBasisText(loadBasisLine.text)
                        .accessibilityIdentifier("load-basis-line")
                } else {
                    loadBasisText(loadBasisLine.text)
                        .hidden()
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func loadBasisText(_ text: String) -> some View {
        Text(text)
            .font(Theme.font(.runline))
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .truncationMode(.tail)
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
                // keyboard without logging (any tap on non-interactive stage space is the same
                // escape). Semantic-only, so no haptic here.
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
        HapticPlayer.shared.play(.input(hitFloor ? Theme.Haptics.skipDud : Theme.Haptics.stepperTick))
    }

    // MARK: - Log capsule / skip

    private var actionControls: some View {
        VStack(spacing: 8) {
            HoldToSkipLogButton(
                logTitle: form.logButtonTitle,
                canLog: form.canLog,
                setState: set.state,
                showsLoggedCheckmark: showsLoggedCheckmark,
                onLogTap: submitLog,
                onSkip: skip
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
        // Dismissal happens here — at action time — never at touch-down: folding the keyboard
        // while the finger is still pressed slides the whole non-scrolling stage down and the
        // capsule escapes the tap before it can resolve (the "Log does nothing with the
        // keyboard open" bug).
        dismissFieldUI()
        guard let log = form.submitLog() else { return }
        HapticPlayer.shared.play(.input(Theme.Haptics.logTap))
        withAnimation(Theme.logButtonCheckmarkAnimation) {
            showsLoggedCheckmark = true
        }
        onLog(log)
    }

    private func skip() {
        dismissFieldUI()
        HapticPlayer.shared.play(.input(Theme.Haptics.skipDud))
        onSkip()
    }

    private func dismissFieldUI() {
        isEditingWeight = false
        weightFieldFocused = false
    }
}

// MARK: - Value rail (Reps / RPE)

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
            .contentShape(.rect(cornerRadius: Theme.Radius.rail))
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
                HapticPlayer.shared.play(.input(Theme.Haptics.railDetentTick))
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
            HapticPlayer.shared.play(.input(Theme.Haptics.railDetentTick))
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
    let setState: SetState
    let showsLoggedCheckmark: Bool
    let onLogTap: () -> Void
    let onSkip: () -> Void

    @State private var gesture = HoldToSkipGesture()
    @State private var skipProgress = 0.0
    @Environment(\.themePalette) private var palette

    var body: some View {
        Group {
            if setState == .skipped {
                skippedBed
            } else {
                logButtonSurface
            }
        }
        .onLongPressGesture(
            minimumDuration: policy.holdDuration,
            maximumDistance: 44,
            pressing: { isPressing in
                apply(isPressing ? gesture.pressBegan(at: .now, policy: policy) : gesture.pressEnded(at: .now))
            },
            perform: { apply(gesture.skipRequested(at: .now)) }
        )
        .contentShape(.rect)
        .onTapGesture { apply(gesture.tapped(at: .now)) }
        .task(id: gesture.nextDeadline) {
            guard let deadline = gesture.nextDeadline else { return }
            do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
            apply(gesture.deadlineReached(at: .now))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityValue(skipProgress > 0 ? "\(Int((skipProgress * 100).rounded()))% Skip" : "")
        .accessibilityHint(presentation.accessibilityHint)
        .accessibilityIdentifier("log-active-set-button")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            apply(gesture.tapped(at: .now))
        }
        .accessibilityAction(named: "Skip") {
            apply(gesture.skipRequested(at: .now))
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
        .forSet(in: setState)
    }

    private func apply(_ effects: [HoldToSkipEffect]) {
        for effect in effects {
            switch effect {
            case .progress(let target, let duration, let linear):
                withAnimation(linear ? .linear(duration: duration) : .easeOut(duration: duration)) {
                    skipProgress = target
                }
            case .log:
                onLogTap()
            case .skip:
                onSkip()
            }
        }
    }
}

extension EnvironmentValues {
    @Entry var showsLoadBasis = false
}
