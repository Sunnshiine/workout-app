import ActivityKit
import Foundation
import SwiftUI

struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        let exerciseName: String
        let prescribedReps: String
        let prescribedLoad: String
        let weightValue: String
        let weightUnit: String
        let setsDone: Int
        let setsTotal: Int
        let variant: DesignVariant
        let appearance: LiveActivityAppearance
        let restStartDate: Date?
        let restEndDate: Date?
        /// Where a Dictation run without opening the app stands; nil when none is showing.
        let dictation: LiveActivityDictation?
    }

    let sessionLabel: String
}

/// What the Lock Screen and the Dynamic Island read back of a Dictation the athlete ran from the
/// Action button, a control, or Siri, with the app closed or the phone locked.
enum LiveActivityDictation: Codable, Hashable, Sendable {
    case listening
    /// The Set Log written, as "235×5 @7", and the Set it went to. The content around it may be
    /// the rest toward another Exercise.
    case logged(String, to: LiveActivityWrittenSet)
    case skipped(LiveActivityWrittenSet)
    /// Why nothing was written.
    case notLogged(String)
    /// The named Session has no Pending Set, so nothing listened.
    case noSetLeft(session: String)
    /// No Session to log into, so nothing listened.
    case noCurrentSession

    var isListening: Bool {
        self == .listening
    }

    /// Which colour the readback takes. The action green is for the mic open and a Set Log that
    /// happened; a skip draws muted on the card, and a press that wrote nothing is no progress, so
    /// those read in the plain text colour (DESIGN.md, The Green Means Action Rule).
    enum Tone: Equatable, Sendable {
        case action
        case quiet
    }

    var tone: Tone {
        switch self {
        case .listening, .logged: .action
        case .skipped, .notLogged, .noSetLeft, .noCurrentSession: .quiet
        }
    }

    /// False when the readback is about the Session rather than a Set: nothing listened, and the
    /// content names no Exercise and no prescription.
    var isAboutASet: Bool {
        switch self {
        case .listening, .logged, .skipped, .notLogged: true
        case .noSetLeft, .noCurrentSession: false
        }
    }

    /// The Set a write went to, which the readback names in place of the content's Exercise.
    var writtenSet: LiveActivityWrittenSet? {
        switch self {
        case .logged(_, let set), .skipped(let set): set
        case .listening, .notLogged, .noSetLeft, .noCurrentSession: nil
        }
    }

    /// The Session a readback about it names.
    var sessionName: String? {
        guard case .noSetLeft(let session) = self else { return nil }
        return session
    }

    var symbolName: String {
        switch self {
        case .listening: "mic.fill"
        case .logged, .skipped, .noSetLeft: "checkmark.circle.fill"
        case .notLogged: "mic.slash.fill"
        case .noCurrentSession: "exclamationmark.circle.fill"
        }
    }

    var headline: String {
        switch self {
        case .listening: "Listening…"
        case .logged(let setLog, _): "Logged \(setLog)"
        case .skipped: "Skipped"
        case .notLogged: "Not logged"
        case .noSetLeft: "No Set left to log"
        case .noCurrentSession: "No Session"
        }
    }

    /// The compact island has room for one short line.
    var compactText: String {
        switch self {
        case .listening: "Listening"
        case .logged(let setLog, _): setLog
        case .skipped: "Skipped"
        case .notLogged: "Not logged"
        case .noSetLeft: "No Set left"
        case .noCurrentSession: "No Session"
        }
    }

    /// Under the headline, where the Exercise is already named above it.
    var detail: String? {
        switch self {
        case .logged(_, let set), .skipped(let set): set.setText
        case .notLogged(let reason): reason
        case .noCurrentSession: "Open WorkoutTracker to choose a Sheet"
        case .listening, .noSetLeft: nil
        }
    }
}

/// The Set a Dictation wrote: what its readback names, apart from the rest the write began.
struct LiveActivityWrittenSet: Codable, Hashable, Sendable {
    let exerciseName: String
    /// The Set's place among its Exercise's Sets, from 1, as its card numbers it.
    let setOrdinal: Int
    let setsTotal: Int

    var setText: String {
        "Set \(setOrdinal) of \(setsTotal)"
    }

    /// The Exercise and the Set, for a surface with no line naming the Exercise.
    var fullText: String {
        "\(exerciseName), \(setText)"
    }
}

enum DesignVariant: String, Codable, Hashable, CaseIterable, Identifiable, Sendable {
    case setProgress
    case nowLifting
    case restTimer
    case restTimerSetsLeft
    case restTimerSetCount
    case restTimerClean

    var id: Self { self }

    var title: String {
        switch self {
        case .setProgress:
            "Set Progress"
        case .nowLifting:
            "Now Lifting"
        case .restTimer:
            "Rest Timer"
        case .restTimerSetsLeft:
            "Rest + Sets Left"
        case .restTimerSetCount:
            "Rest + Set Count"
        case .restTimerClean:
            "Rest Clean"
        }
    }

    var isRestTimer: Bool {
        switch self {
        case .restTimer, .restTimerSetsLeft, .restTimerSetCount, .restTimerClean:
            true
        case .setProgress, .nowLifting:
            false
        }
    }
}

enum LiveActivityAppearance: String, Codable, Hashable, CaseIterable, Identifiable, Sendable {
    case dark
    case light

    var id: Self { self }

    var title: String {
        switch self {
        case .dark:
            "Dark"
        case .light:
            "Light"
        }
    }
}

struct LiveActivityColors {
    let accent: Color
    let accentText: Color
    let background: Color
    let panelFill: Color
    let track: Color
    let primaryText: Color
    let secondaryText: Color
    let islandPrimaryText: Color
    let islandSecondaryText: Color
}

enum LiveActivityPalette {
    static func colors(for appearance: LiveActivityAppearance) -> LiveActivityColors {
        switch appearance {
        case .dark:
            dark
        case .light:
            light
        }
    }

    private static let dark = LiveActivityColors(
        accent: Color(red: 0.45, green: 1.0, blue: 0.72),
        accentText: Color(red: 0.02, green: 0.12, blue: 0.07),
        background: Color(red: 0.02, green: 0.03, blue: 0.025),
        panelFill: Color(red: 0.06, green: 0.10, blue: 0.08),
        track: Color.white.opacity(0.16),
        primaryText: .white,
        secondaryText: Color.white.opacity(0.68),
        islandPrimaryText: .white,
        islandSecondaryText: Color.white.opacity(0.68)
    )

    private static let light = LiveActivityColors(
        accent: Color(red: 0.0, green: 0.48, blue: 0.30),
        accentText: .white,
        background: Color(red: 0.92, green: 0.98, blue: 0.94),
        panelFill: Color(red: 0.80, green: 0.93, blue: 0.85),
        track: Color.black.opacity(0.12),
        primaryText: Color(red: 0.04, green: 0.11, blue: 0.07),
        secondaryText: Color.black.opacity(0.58),
        islandPrimaryText: .white,
        islandSecondaryText: Color.white.opacity(0.68)
    )
}

extension LiveActivityColors {
    /// The readback's text in its tone, on the Lock Screen card or the island.
    func readbackText(_ tone: LiveActivityDictation.Tone, onIsland: Bool) -> Color {
        switch tone {
        case .action: accent
        case .quiet: onIsland ? islandPrimaryText : primaryText
        }
    }

    /// The readback's symbol in its tone: the glyph's colour over its circle's fill.
    func readbackSymbol(_ tone: LiveActivityDictation.Tone) -> (glyph: Color, circle: Color) {
        switch tone {
        case .action: (accentText, accent)
        case .quiet: (primaryText, track)
        }
    }
}

extension WorkoutActivityAttributes.ContentState {
    var liveActivityColors: LiveActivityColors {
        LiveActivityPalette.colors(for: appearance)
    }

    var normalizedProgress: Double {
        guard setsTotal > 0 else { return 0 }
        return min(max(Double(setsDone) / Double(setsTotal), 0), 1)
    }

    var setProgressText: String {
        "\(setsDone)/\(setsTotal)"
    }

    var setsLeft: Int {
        max(setsTotal - setsDone, 0)
    }

    var setsLeftText: String {
        setsLeft == 1 ? "1 Set left" : "\(setsLeft) Sets left"
    }

    var restContextText: String? {
        switch variant {
        case .restTimerSetsLeft:
            setsLeftText
        case .restTimerSetCount:
            "\(setProgressText) sets"
        case .setProgress, .nowLifting, .restTimer, .restTimerClean:
            nil
        }
    }

    var weightText: String {
        "\(weightValue) \(weightUnit)"
    }

    var prescribedRepsText: String {
        let reps = prescribedReps.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reps.isEmpty else { return "" }
        guard reps.localizedCaseInsensitiveContains("rep") == false else { return reps }
        guard reps.caseInsensitiveCompare("AMRAP") != .orderedSame else { return reps }
        return reps == "1" ? "1 rep" : "\(reps) reps"
    }

    var prescriptionText: String {
        [prescribedRepsText, prescribedLoad]
            .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            .joined(separator: " / ")
    }

    var restInterval: ClosedRange<Date>? {
        guard let restEndDate else { return nil }
        let now = Date.now
        guard restEndDate > now else { return restEndDate...restEndDate }
        return now...restEndDate
    }

    var isRestReady: Bool {
        isRestReady(at: Date.now)
    }

    func isRestReady(at date: Date) -> Bool {
        guard let restEndDate else { return false }
        return date >= restEndDate
    }

    var restProgress: Double {
        restProgress(at: Date.now)
    }

    func restProgress(at date: Date) -> Double {
        guard let restStartDate, let restEndDate else { return 0 }
        let totalDuration = restEndDate.timeIntervalSince(restStartDate)
        guard totalDuration > 0 else { return 0 }
        let elapsed = date.timeIntervalSince(restStartDate)
        return min(max(elapsed / totalDuration, 0), 1)
    }
}
