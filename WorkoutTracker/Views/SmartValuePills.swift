import SwiftUI
import UIKit

struct SmartValuePills: View {
    private enum FocusedPill {
        case weight
        case reps
    }

    let set: ExerciseSet
    let onLog: (SetLog) -> Void
    let onSkip: () -> Void
    let onDelete: () -> Void

    @State private var form: SmartValuePillsForm
    @State private var editingPill: FocusedPill?
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
        showsLoggedCheckmarkInitially: Bool = false
    ) {
        self.set = set
        self.onLog = onLog
        self.onSkip = onSkip
        self.onDelete = onDelete
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
            WeightedValuePillRow(spacing: Theme.pillSpacing, weightColumnFraction: 2.0 / 3.0) {
                weightPill
                repsPill
            }

            RPEScaleScroller(
                presentation: RPEScalePresentation(
                    prescribedRPE: form.prescribedRPE,
                    selection: form.rpeText
                ),
                onSelect: { form.rpeText = $0 }
            )

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
    }

    private var weightPill: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weight")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if form.allowsWeightStepping {
                    stepperButton("minus", by: -form.fineWeightIncrement, id: "weight-decrement")
                }

                weightValueField

                if form.allowsWeightStepping {
                    stepperButton("plus", by: form.fineWeightIncrement, id: "weight-increment")
                }
            }
        }
        .modifier(PillChrome(isFocused: editingPill == .weight, isInvalid: form.invalidFields.contains(.weight)))
        .opacity(dimmedOpacity(for: .weight))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var weightValueField: some View {
        if editingPill == .weight {
            TextField(form.weightDisplay, text: $form.weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.title3.weight(.bold))
                .foregroundStyle(palette.valueText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .focused($focusedPill, equals: .weight)
                .accessibilityIdentifier("weight-pill")
        } else {
            Text(form.weightDisplay)
                .font(.title3.weight(.bold))
                .foregroundStyle(palette.valueText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
                .onTapGesture { editingPill = .weight }
                .accessibilityLabel("Weight, \(form.weightDisplay)")
                .accessibilityIdentifier("weight-pill")
                .accessibilityAddTraits(.isButton)
        }
    }

    private func stepperButton(_ systemName: String, by increment: Double, id: String) -> some View {
        Button {
            form.adjustWeight(by: increment)
        } label: {
            Image(systemName: systemName)
                .font(.headline.weight(.bold))
                .foregroundStyle(palette.accent)
                .frame(width: 36, height: 36)
                .background(palette.pillFill, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private var repsPill: some View {
        let isPlaceholder = form.isRepsDisplayingPlaceholder && editingPill != .reps

        return VStack(alignment: .center, spacing: 8) {
            Text("Reps")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            if editingPill == .reps {
                TextField(form.repsDisplay, text: $form.repsText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(palette.valueText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .focused($focusedPill, equals: .reps)
            } else {
                Text(form.repsDisplay)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(isPlaceholder ? Color.secondary : palette.valueText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .modifier(
            PillChrome(
                isFocused: editingPill == .reps,
                isInvalid: form.invalidFields.contains(.reps),
                alignment: .center
            )
        )
        .opacity(dimmedOpacity(for: .reps))
        .contentShape(.rect)
        .onTapGesture { editingPill = .reps }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reps, \(form.repsDisplay)")
        .accessibilityIdentifier("reps-pill")
        .accessibilityAddTraits(.isButton)
    }

    /// Dims the field that is not being typed in, so the focused field reads as active.
    private func dimmedOpacity(for pill: FocusedPill) -> Double {
        guard let editingPill, editingPill != pill else { return 1 }
        return 0.5
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
    }
}

private struct WeightedValuePillRow: Layout {
    let spacing: CGFloat
    let weightColumnFraction: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }

        let totalWidth = proposal.width ?? intrinsicWidth(for: subviews)
        let columnWidths = columns(for: totalWidth)
        let heights = subviews.enumerated().map { index, subview in
            subview.sizeThatFits(
                ProposedViewSize(width: columnWidths[index], height: proposal.height)
            ).height
        }

        return CGSize(width: totalWidth, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }

        let columnWidths = columns(for: bounds.width)
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                proposal: ProposedViewSize(width: columnWidths[index], height: bounds.height)
            )
            x += columnWidths[index] + spacing
        }
    }

    private func intrinsicWidth(for subviews: Subviews) -> CGFloat {
        subviews.reduce(0) { width, subview in
            width + subview.sizeThatFits(.unspecified).width
        } + spacing
    }

    private func columns(for totalWidth: CGFloat) -> [CGFloat] {
        let availableWidth = max(totalWidth - spacing, 0)
        let weightWidth = floor(availableWidth * weightColumnFraction)
        return [weightWidth, availableWidth - weightWidth]
    }
}

/// Pill background plus a stroke that turns accent while focused and red when invalid.
private struct PillChrome: ViewModifier {
    let isFocused: Bool
    let isInvalid: Bool
    var alignment: Alignment = .leading
    @Environment(\.themePalette) private var palette

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, minHeight: Theme.pillMinHeight, alignment: alignment)
            .padding(.horizontal, 12)
            .background(palette.pillFill, in: .rect(cornerRadius: Theme.pillCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.pillCornerRadius)
                    .strokeBorder(strokeColor, lineWidth: strokeWidth)
            )
    }

    private var strokeColor: Color {
        if isInvalid { return palette.danger }
        return isFocused ? palette.accent : palette.pillStroke
    }

    private var strokeWidth: CGFloat {
        isInvalid || isFocused ? 2 : 1
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
                palette.danger.opacity(0.86)
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
                        .background(palette.danger.opacity(0.86), in: .capsule)
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
        switch presentation.tone {
        case .primary: palette.accent
        case .incomplete: palette.pillFill
        }
    }

    private var logForegroundStyle: Color {
        switch presentation.tone {
        case .primary: palette.accentDarkText
        case .incomplete: palette.valueText
        }
    }

    private var logStrokeStyle: Color {
        switch presentation.tone {
        case .primary: .clear
        case .incomplete: palette.pillStroke
        }
    }

    private var logStrokeWidth: CGFloat {
        switch presentation.tone {
        case .primary: 0
        case .incomplete: 1
        }
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
