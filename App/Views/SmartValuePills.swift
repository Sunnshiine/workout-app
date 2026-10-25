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
    let inputDismissalRequestID: Int
    let dictation: SetCardDictation
    let onDismissDictation: () -> Void
    /// Takes what the card shows each time it changes, which fills what a Spoken Set leaves unsaid.
    let onShow: (SetLogDraft) -> Void

    @State private var form: SmartValuePillsForm
    @State private var weightFieldMount = WeightFieldMount()
    @Environment(\.themePalette) private var palette
    @Environment(\.showsLoadBasis) private var showsLoadBasis
    @FocusState private var weightFieldFocused: Bool

    init(
        set: ExerciseSet,
        mode: SetCardMode = .logging,
        suggestion: LoadSuggestion,
        onLog: @escaping (SetLog) -> Void,
        onSkip: @escaping () -> Void,
        inputDismissalRequestID: Int = 0,
        dictation: SetCardDictation = .ready,
        onDismissDictation: @escaping () -> Void = {},
        onShow: @escaping (SetLogDraft) -> Void = { _ in }
    ) {
        self.set = set
        self.mode = mode
        self.suggestion = suggestion
        self.onLog = onLog
        self.onSkip = onSkip
        self.inputDismissalRequestID = inputDismissalRequestID
        self.dictation = dictation
        self.onDismissDictation = onDismissDictation
        self.onShow = onShow
        _form = State(initialValue: SmartValuePillsForm(set: set, suggestion: suggestion))
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

            actionRow
        }
        .disabled(!presentation.editsValues)
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
        .onChange(of: dictation) { _, later in
            guard case .filled(let heard) = later else { return }
            form.fill(heard)
            onDismissDictation()
        }
        .onChange(of: weightFieldFocused) { _, focused in
            weightFieldMount.focusChanged(to: focused)
        }
        .onChange(of: weightFieldMount.focusRequests) {
            weightFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            weightFieldMount.keyboardDidHide()
        }
        .onDisappear(perform: commitChangedDraftIfNeeded)
        .preference(key: EditingWeightPreferenceKey.self, value: weightFieldFocused)
        .onChange(of: form.draft, initial: true) { _, draft in
            onShow(draft)
        }
    }

    private var presentation: SetCardPresentation {
        SetCardPresentation(mode: mode, set: set)
    }

    private var repsPresentation: RepsScalePresentation {
        RepsScalePresentation(prescribedReps: form.prescribedReps, selection: form.repsText)
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

    private var weightValue: some View {
        Text(verbatim: "0")
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .frame(maxWidth: .infinity)
            .overlay {
                // A mounted text field stays in the accessibility tree whatever its modifiers say.
                if weightFieldMount.mountsField {
                    TextField(form.weightDisplay, text: $form.weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .focused($weightFieldFocused)
                        .opacity(weightFieldFocused ? 1 : 0)
                        .accessibilityIdentifier("weight-pill")
                }
            }
            .overlay {
                if !weightFieldFocused {
                    Text(form.weightDisplay)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(.rect)
                        .onTapGesture {
                            weightFieldMount.tapped()
                        }
                        .accessibilityLabel("Weight, \(form.weightDisplay)")
                        .accessibilityIdentifier("weight-pill")
                        .accessibilityAddTraits(.isButton)
                }
            }
            .font(Theme.font(.weightEntry))
            .foregroundStyle(weightForeground)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            // The decimal pad has no return key, so Done is the way out. Attached outside the weight
            // font and colour, which Done would otherwise inherit.
            .toolbar {
                if weightFieldMount.showsDone {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(action: dismissFieldUI) {
                            Label("Done", systemImage: "keyboard.chevron.compact.down")
                                .labelStyle(.iconOnly)
                        }
                        .accessibilityIdentifier("weight-keyboard-done")
                    }
                }
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

    @ViewBuilder
    private var actionRow: some View {
        if let caption = dictation.caption {
            spokenSetCapsule(caption)
        } else {
            logAction(presentation.actionRow(for: form))
        }
    }

    @ViewBuilder
    private func logAction(_ row: SetCardPresentation.ActionRow) -> some View {
        switch row {
        case .logged(let line):
            loggedSetCapsule(line)
        case .incompleteDraft:
            loggedSetCapsule(SetCardPresentation.incompleteDraftHint)
        case .log, .skipped:
            HoldToSkipLogButton(
                logTitle: form.logButtonTitle,
                canLog: form.canLog,
                setState: set.state,
                onLogTap: submitLog,
                onSkip: skip
            )
        }
    }

    private func loggedSetCapsule(_ line: String) -> some View {
        Text(line)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 16)
            .logCapsuleMetrics()
            .foregroundStyle(palette.textSecondary)
            .overlay {
                Capsule().strokeBorder(palette.pillStroke, lineWidth: 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line)
            .accessibilityIdentifier("logged-set-capsule")
    }

    /// What the mic hears in place of the Log button, in its frame, and what it heard when nothing
    /// was written until a tap brings the Log button back.
    private func spokenSetCapsule(_ caption: String) -> some View {
        let isListening = dictation.isListening
        return Text(caption)
            .lineLimit(1)
            .truncationMode(.head)
            .padding(.horizontal, 16)
            .logCapsuleMetrics()
            .foregroundStyle(isListening ? palette.textPrimary : palette.textSecondary)
            .background(palette.pillFill, in: .capsule)
            .overlay {
                Capsule().strokeBorder(isListening ? palette.action : palette.pillStroke, lineWidth: isListening ? 2 : 1)
            }
            .contentShape(.capsule)
            .onTapGesture {
                if !isListening { onDismissDictation() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(caption)
            .accessibilityHint(isListening ? "" : "Shows the Log button")
            .accessibilityAction {
                if !isListening { onDismissDictation() }
            }
            .accessibilityIdentifier("spoken-set-capsule")
    }

    /// Reviewing an already-logged Set commits silently: any changed, valid draft is written when
    /// the card leaves the screen (collapse or navigation), with the header's Saved label as feedback.
    private func commitChangedDraftIfNeeded() {
        guard presentation.commitsChangesOnDisappear, let log = form.changedValidLog(toSaveOver: set) else { return }
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
        onLog(log)
    }

    private func skip() {
        dismissFieldUI()
        HapticPlayer.shared.play(.input(Theme.Haptics.skipDud))
        onSkip()
    }

    private func dismissFieldUI() {
        weightFieldFocused = false
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
    let onLogTap: () -> Void
    let onSkip: () -> Void

    @State private var gesture = HoldToSkipGesture()
    @State private var skipProgress = 0.0
    @Environment(\.themePalette) private var palette

    var body: some View {
        Group {
            if presentation.showsSkippedBed {
                skippedBed
            } else {
                logButtonSurface
            }
        }
        .onLongPressGesture(
            minimumDuration: presentation.longPressDuration,
            maximumDistance: HoldToSkipGesture.maximumTravel,
            pressing: { isPressing in
                apply(isPressing ? gesture.pressBegan(at: .now, policy: presentation.holdPolicy) : gesture.pressEnded(at: .now))
            },
            perform: { apply(gesture.deadlineReached(at: .now)) }
        )
        .contentShape(.rect)
        .onTapGesture { apply(gesture.tapped(at: .now)) }
        .simultaneousGesture(
            DragGesture(minimumDistance: HoldToSkipGesture.maximumTravel)
                .onChanged { apply(gesture.pressMoved(by: $0.translation)) }
                .onEnded { _ in apply(gesture.pressEnded(at: .now)) }
        )
        .task(id: gesture.nextDeadline) {
            guard let deadline = gesture.nextDeadline else { return }
            do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
            apply(gesture.deadlineReached(at: .now))
        }
        .onDisappear { gesture.disappeared() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityValue(presentation.accessibilityValue)
        .accessibilityHint(presentation.accessibilityHint)
        .accessibilityIdentifier("log-active-set-button")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            apply(gesture.tapped(at: .now))
        }
        .accessibilityActions {
            if presentation.offersSkip {
                Button("Skip") { apply(gesture.skipRequested(at: .now)) }
            }
        }
    }

    private var logButtonSurface: some View {
        buttonContent
            .logCapsuleMetrics()
            .foregroundStyle(logForegroundStyle)
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
            .animation(.snappy(duration: 0.16)) { $0.scaleEffect(gesture.isPressing ? 0.97 : 1) }
    }

    /// The dashed "empty bed" the skipped state settles into (§5.3): transparent, muted text.
    private var skippedBed: some View {
        Text("Skipped")
            .logCapsuleMetrics()
            .foregroundStyle(palette.textSecondary)
            .overlay {
                Capsule()
                    .strokeBorder(palette.skipStroke, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
    }

    private var buttonContent: some View {
        ZStack {
            Text(logTitle)
                .opacity(presentation.logOpacity)

            // accessibilityHidden leaves this crossfade text in the tree, an empty label drops it.
            Text("Skipped")
                .opacity(presentation.skipOpacity)
                .accessibilityLabel("")
        }
        .frame(maxWidth: .infinity)
    }

    private var presentation: HoldToSkipButtonPresentation {
        HoldToSkipButtonPresentation(progress: skipProgress, logTitle: logTitle, canLog: canLog, setState: setState)
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

    private func apply(_ effects: [HoldToSkipEffect]) {
        for effect in effects {
            switch effect {
            case .clearFill:
                skipProgress = 0
            case .revealFill(let duration):
                withAnimation(.linear(duration: duration)) {
                    skipProgress = 1
                }
            case .retreatFill:
                withAnimation(.easeOut(duration: Theme.Motion.holdToSkipRetreat)) {
                    skipProgress = 0
                }
            case .log:
                onLogTap()
            case .skip:
                onSkip()
            }
        }
    }
}

extension View {
    fileprivate func logCapsuleMetrics() -> some View {
        font(Theme.font(.logCapsule))
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
    }
}

extension EnvironmentValues {
    @Entry var showsLoadBasis = false
}
