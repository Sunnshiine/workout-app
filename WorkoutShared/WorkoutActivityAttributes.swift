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
    }

    let sessionLabel: String
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
        setsLeft == 1 ? "1 set left" : "\(setsLeft) sets left"
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
        return "\(reps) reps"
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
