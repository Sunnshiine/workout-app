import SwiftData
import SwiftUI

/// The card's mic, present only while its Set can be said.
struct SetCardMic {
    let dictation: SetCardDictation
    /// True while the Action button, Siri, or the Live Activity waits for this card to listen.
    let startsHandsFree: Bool
    let start: () -> Void
    /// Reports what the card shows as it changes, which fills what the athlete leaves unsaid.
    let shows: (SetLogDraft) -> Void
    let finish: () async -> SetDictation.Outcome?
    let listenHandsFree: () async -> SetDictation.Outcome?
    let cancel: () async -> Void
    let dismiss: () -> Void
}

struct ActiveSetCard: View {
    private struct PillsIdentity: Hashable {
        let set: PersistentIdentifier
        let mode: SetCardMode
    }

    let set: ExerciseSet
    let setOrdinal: Int
    let setCount: Int
    var mode: SetCardSlot.Mode = .logging
    var mic: SetCardMic?
    var timedEffort: SetCardTimedEffort?  // default: no control, the answer for a Set with no Timed Effort
    let onLog: (SetLog) -> Void
    let onSkip: () -> Void
    let onDelete: () -> Void
    let onTouchWhileHeld: () -> Void
    let onClearMenuOpened: () -> Void
    let onClearMenuClosed: () -> Void
    @Environment(LastPerformedLookupStore.self) private var history
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var inputDismissalRequestID = 0
    @GestureState private var isPressingMic = false

    private static let headTargetSize: CGFloat = 44
    private static let headTargetOverhang: CGFloat = 12

    private var setCardMode: SetCardMode {
        mode.cardMode
    }

    /// The running countdown cuts in over the card's values in their frame, so the card holds still.
    private var countdownRun: CountdownRun? {
        timedEffort?.countdown.run
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            SmartValuePills(
                set: set,
                mode: setCardMode,
                suggestion: LoadSuggestionEngine.suggest(for: set, history: history.snapshot),
                onLog: onLog,
                onSkip: onSkip,
                inputDismissalRequestID: inputDismissalRequestID,
                dictation: mic?.dictation ?? .ready,
                onDismissDictation: { mic?.dismiss() },
                onShow: { mic?.shows($0) }
            )
            .id(PillsIdentity(set: set.persistentModelID, mode: setCardMode))
            .opacity(countdownRun == nil ? 1 : 0)
            .accessibilityHidden(countdownRun != nil)
            .overlay {
                if mode == .heldAfterSpokenWrite { heldValuesCover }
                if let countdownRun, let timedEffort {
                    EffortCountdownView(run: countdownRun, onCancel: timedEffort.cancel)
                }
            }
        }
        .onChange(of: isPressingMic) { _, isPressing in
            if isPressing { beginPress() } else { endPress() }
        }
        .onChange(of: mic?.startsHandsFree ?? false, initial: true) { _, starts in
            if starts { listenHandsFree() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardContentPadding)
        .background(palette.surface, in: .rect(cornerRadius: Theme.Radius.activeSetCard))
        .themeElevation(palette.surfaceShadow, in: RoundedRectangle(cornerRadius: Theme.Radius.activeSetCard))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("active-set-card")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Set \(setOrdinal)")
                .font(Theme.font(.setNumber, at: dynamicTypeSize))
                .foregroundColor(palette.textPrimary)
                + Text(" of \(setCount)")
                .font(Theme.font(.setOf, at: dynamicTypeSize))
                .foregroundColor(palette.textSecondary)

            Spacer(minLength: 0)
        }
        .background {
            Color.clear
                .contentShape(.rect)
                .onTapGesture(perform: dismissInputIfLogging)
                .simultaneousGesture(touchWhileHeld, including: touchMask)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .trailing) { headTrailingSlot }
    }

    /// A touch on the held card moves it on; the Clear menu sits outside it, so undo stays a touch away.
    private var touchWhileHeld: some Gesture {
        DragGesture(minimumDistance: 0).onChanged { _ in onTouchWhileHeld() }
    }

    private var touchMask: GestureMask {
        mode == .heldAfterSpokenWrite ? .all : .subviews
    }

    /// The held Set's values take no edit, so a touch on them moves the card on.
    private var heldValuesCover: some View {
        Color.clear
            .contentShape(.rect)
            .gesture(touchWhileHeld)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var headTrailingSlot: some View {
        switch mode.headAccessory(for: set) {
        case .none:
            HStack(spacing: 4) {
                if let timedEffort {
                    TimedEffortControl(timedEffort: timedEffort, targetHeight: Self.headTargetSize)
                }
                if let mic {
                    micControl(mic.dictation)
                }
            }
        case .saved:
            HStack(spacing: 0) {
                savedConfirmation
                if let mic {
                    micControl(mic.dictation)
                }
            }
        case .clearMenu:
            clearMenu
        case .savedAndClearMenu:
            HStack(spacing: 0) {
                savedConfirmation
                HeldClearMenu(
                    tint: palette.textSecondary,
                    onOpened: onClearMenuOpened,
                    onClosed: onClearMenuClosed,
                    onClear: onDelete
                )
                .frame(width: Self.headTargetSize, height: Self.headTargetSize)
                .padding(.trailing, -Self.headTargetOverhang)
            }
        }
    }

    private var savedConfirmation: some View {
        Label("Saved", systemImage: "checkmark.circle.fill")
            .themeFont(.setOf)
            .foregroundStyle(palette.actionInk)
    }

    private var clearMenu: some View {
        Menu {
            Button("Clear", role: .destructive, action: onDelete)
        } label: {
            Image(systemName: "ellipsis")
                .imageScale(.large)
                .foregroundStyle(palette.textSecondary)
                .frame(width: Self.headTargetSize, height: Self.headTargetSize)
                .contentShape(.rect)
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("clear-logged-set-menu")
        .padding(.trailing, -Self.headTargetOverhang)
    }

    /// Press and hold to talk. VoiceOver's activation starts listening and the next one finishes.
    private func micControl(_ dictation: SetCardDictation) -> some View {
        Image(systemName: dictation.isListening ? "mic.fill" : "mic")
            .imageScale(.large)
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            .foregroundStyle(dictation.isListening ? palette.action : palette.textSecondary)
            .frame(width: Self.headTargetSize, height: Self.headTargetSize)
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0).updating($isPressingMic) { _, isPressing, _ in isPressing = true })
            .onDisappear(perform: cancelPress)
            .accessibilityElement()
            .accessibilityLabel("Say Set")
            .accessibilityValue(dictation.isListening ? "Listening" : "")
            .accessibilityHint("Hold and say your Set, like 185 for 5 at 8")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if dictation.isListening { endPress() } else { beginPress() }
            }
            .accessibilityIdentifier("say-set-button")
            .padding(.trailing, -Self.headTargetOverhang)
    }

    private func beginPress() {
        guard let mic else { return }
        dismissInputIfLogging()
        HapticPlayer.shared.play(SetDictation.startHaptic)
        mic.start()
    }

    private func endPress() {
        guard let mic else { return }
        Task {
            guard let outcome = await mic.finish() else { return }
            HapticPlayer.shared.play(outcome.haptic)
        }
    }

    private func listenHandsFree() {
        guard let mic else { return }
        dismissInputIfLogging()
        HapticPlayer.shared.play(SetDictation.startHaptic)
        Task {
            guard let outcome = await mic.listenHandsFree() else { return }
            HapticPlayer.shared.play(outcome.haptic)
        }
    }

    /// A press whose mic leaves the screen writes nothing.
    private func cancelPress() {
        guard let mic else { return }
        Task { await mic.cancel() }
    }

    private func dismissInputIfLogging() {
        if case .logging = mode {
            inputDismissalRequestID += 1
        }
    }
}
