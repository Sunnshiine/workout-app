import SwiftUI

/// The Lock Screen while a Dictation the athlete ran without the app listens for the Set, and once
/// a run or a chip has an answer: the readback under the Exercise of the Set it is about, over the
/// rest when a logged Set began one, else over the Exercise's Sets. Its bottom row holds no control,
/// so a second tap of a double tap finds nothing under the thumb.
struct DictationLockScreenView: View {
    let state: WorkoutActivityAttributes.ContentState
    let dictation: LiveActivityDictation

    var body: some View {
        let colors = state.liveActivityColors

        LockScreenCardLayout(state: state, exerciseName: dictation.writtenSet?.exerciseName ?? state.exerciseName) {
            DictationReadback(dictation: dictation, colors: colors, style: .lockScreen(prescription: state.prescriptionText))
        } mic: {
            if dictation.isListening {
                DictationSymbol(dictation: dictation, colors: colors, diameter: LockScreenCardMetrics.controlSize)
            } else {
                SaySetButton(state: state, diameter: LockScreenCardMetrics.controlSize)
            }
        } bottomRow: {
            DictationProgress(state: state, dictation: dictation, style: .lockScreen)
        }
    }
}

struct DictationReadback: View {
    enum Style {
        case island
        /// With no detail of its own, a readback about a Set reads its prescription, which holds the
        /// line that Set's card keeps.
        case lockScreen(prescription: String?)
    }

    let dictation: LiveActivityDictation
    let colors: LiveActivityColors
    let style: Style

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(dictation.headline)
                .liveActivityFont(.figure)
                .foregroundStyle(colors.readbackText(dictation.tone, onIsland: isOnIsland))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            switch style {
            case .island:
                if let detail = dictation.islandDetail {
                    Text(detail)
                        .liveActivityFont(.reference)
                        .foregroundStyle(colors.islandSecondaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            case .lockScreen(let prescription):
                if let detail = dictation.detail ?? prescription {
                    Text(detail.isEmpty ? " " : detail)
                        .liveActivityFont(.reference)
                        .foregroundStyle(colors.secondaryText)
                        .lineLimit(hasRoomForASecondLine ? 2 : 1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("live-activity-dictation")
    }

    private var isOnIsland: Bool {
        if case .island = style { return true }
        return false
    }

    /// A long reason wraps only where the card stays under the 160pt the system gives it.
    private var hasRoomForASecondLine: Bool {
        dynamicTypeSize <= .large
    }
}

/// The mic while listening, where the Say Set button sits otherwise.
struct DictationSymbol: View {
    let dictation: LiveActivityDictation
    let colors: LiveActivityColors
    let diameter: CGFloat

    var body: some View {
        let symbol = colors.readbackSymbol(dictation.tone)
        Image(systemName: dictation.symbolName)
            .font(.system(size: diameter * 0.45, weight: .semibold))
            .foregroundStyle(symbol.glyph)
            .frame(width: diameter, height: diameter)
            .background(symbol.circle, in: Circle())
            .accessibilityLabel(dictation.headline)
    }
}

/// The rest when a logged Set began one, else the Exercise's Sets. The Lock Screen shows the rest's
/// digits on its first line, and the island here.
struct DictationProgress: View {
    enum Style {
        case island
        case lockScreen
    }

    let state: WorkoutActivityAttributes.ContentState
    let dictation: LiveActivityDictation
    let style: Style

    var body: some View {
        if state.restEndDate != nil {
            switch style {
            case .island:
                // A timer Text asks for every point an HStack offers, so without a fixed width the
                // bar and the Sets left beside it drew at zero width.
                HStack(spacing: 8) {
                    RestCountdownText(state: state)
                        .liveActivityFont(.figure)
                        .foregroundStyle(state.liveActivityColors.islandPrimaryText)
                        .frame(width: 52, alignment: .leading)

                    RestProgressWithContext(state: state, style: .island, context: nextSetText)
                }
            case .lockScreen:
                RestProgressWithContext(state: state, style: .lockScreen, context: nextSetText)
            }
        } else {
            SegmentedSets(done: state.setsDone, total: state.setsTotal, colors: state.liveActivityColors)
        }
    }

    /// The rest after a write can lead to another Exercise, which it names. Within the Exercise the
    /// card already names, it counts Sets as any rest does.
    private var nextSetText: String? {
        guard let written = dictation.writtenSet, written.exerciseName != state.exerciseName else { return nil }
        return "Next: \(state.exerciseName)"
    }
}
