import SnapshotTesting
import SwiftUI
import Testing

@testable import WorkoutTracker

/// The Block grid — the focus week — against picks block-grid-focus4-d-2d / -3d / -6d
/// (DESIGN.md §5.5), at the three picked day-counts and in both appearances.
///
/// The one Week holding the Current Session expands into full, wordless tiles under morning
/// light (`focusCardFill` + the cream `focusCardGlowRim`); the current tile alone carries the
/// sunlit-hour `sunGlow`; every other Week collapses to a shaded card (`weekCardShade` + `cardLow`)
/// with a mini day-strip; the page sunbeam and the tiles' top-light complete the sunlit hour.
/// At Night the room re-lights by the Room Re-lights Rule — foliage tiles, deep-ink text — the
/// carried slice-8 debt this slice validates on the full grid for the first time (#490, §11).
///
/// Closes the fixture gap (§11): before this the Block grid had only a lone `SessionTile` baseline.
@MainActor
@Suite(.snapshots(record: .never))
struct BlockGridVisualTests {
    @Test func twoDayGridMatchesVisualBaseline() throws {
        try assertGridSnapshot(fixture: .twoDay, appearance: .day, colorScheme: .light)
    }

    @Test func twoDayGridMatchesNightVisualBaseline() throws {
        try assertGridSnapshot(fixture: .twoDay, appearance: .night, colorScheme: .dark)
    }

    @Test func threeDayGridMatchesVisualBaseline() throws {
        try assertGridSnapshot(fixture: .threeDay, appearance: .day, colorScheme: .light)
    }

    @Test func threeDayGridMatchesNightVisualBaseline() throws {
        try assertGridSnapshot(fixture: .threeDay, appearance: .night, colorScheme: .dark)
    }

    @Test func sixDayGridMatchesVisualBaseline() throws {
        try assertGridSnapshot(fixture: .sixDay, appearance: .day, colorScheme: .light)
    }

    @Test func sixDayGridMatchesNightVisualBaseline() throws {
        try assertGridSnapshot(fixture: .sixDay, appearance: .night, colorScheme: .dark)
    }

    private func assertGridSnapshot(
        fixture: GridFixture,
        appearance: Theme.Appearance,
        colorScheme: ColorScheme,
        testName: String = #function
    ) throws {
        let built = fixture.build()
        BlockGridFixtureRetainer.retain(built.block)
        // BlockOverviewView resolves its WorkoutStore environment eagerly on the iOS 27 offscreen
        // render, so inject one; the store's own Block is unused — the view renders the passed-in
        // fixture block. Only tapping a tile would touch the store, and the render never taps.
        let scenario = try WorkoutScenarios.freshConfiguredApp()
        BlockGridFixtureRetainer.retain(scenario.store)

        let view = NavigationStack {
            BlockOverviewView(block: built.block, currentSession: built.currentSession)
        }
        .environment(scenario.store)
        .environment(\.themePalette, Theme.palette(for: appearance))
        .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
        .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)
        .preferredColorScheme(colorScheme)

        assertSnapshot(
            of: view,
            as: .image(
                precision: WorkoutVisualBaseline.labelAntialiasingPrecision,
                layout: .device(config: .workoutVisualBaseline)
            ),
            testName: testName
        )
    }
}

// MARK: - Fixtures

/// A day's target state in a fixture Week, so each grid is built as exactly the tile states the
/// pick shows without threading logged Sets by hand.
private enum FixtureDay {
    case complete
    case partial // two logged Sets of four → a half-risen foot
    case available // uploaded, untouched — a quiet available tile / empty mini bar
    case current // the Current Session — the cream-bud current tile with the sunlit rim
    case unavailable // an un-uploaded day — the dashed empty bed
}

private enum GridFixture {
    case twoDay
    case threeDay
    case sixDay

    /// Each fixture mirrors its pick: Week 2 is the focus, and the header/summary counts fall out
    /// of the day states (e.g. 6-day: "7 of 24 · 8 not uploaded", Week 2 "2 of 6").
    var weeks: [[FixtureDay]] {
        switch self {
        case .twoDay:
            return [
                [.complete, .partial],
                [.partial, .current],
                [.available, .unavailable],
                [.available, .unavailable]
            ]
        case .threeDay:
            return [
                [.complete, .complete, .partial],
                [.complete, .partial, .current],
                [.available, .available, .unavailable],
                [.available, .unavailable, .unavailable]
            ]
        case .sixDay:
            return [
                [.complete, .complete, .complete, .complete, .complete, .partial],
                [.complete, .complete, .partial, .current, .available, .available],
                [.available, .available, .available, .unavailable, .unavailable, .unavailable],
                [.available, .unavailable, .unavailable, .unavailable, .unavailable, .unavailable]
            ]
        }
    }

    func build() -> (block: Block, currentSession: Session?) {
        let block = Block(tabName: "Block 27", squatTM: nil, benchTM: nil, deadliftTM: nil)
        var current: Session?
        block.weeks = weeks.enumerated().map { weekIndex, days in
            let week = Week(number: weekIndex + 1)
            week.sessions = days.enumerated().map { dayIndex, day in
                let session = makeSession(dayNumber: dayIndex + 1, day: day)
                if day == .current { current = session }
                return session
            }
            return week
        }
        return (block, current)
    }

    private func makeSession(dayNumber: Int, day: FixtureDay) -> Session {
        let session = Session(dayNumber: dayNumber, date: nil)
        guard day != .unavailable else {
            session.exercises = [] // an un-uploaded day carries no Exercises
            return session
        }
        let exercise = Exercise(name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil, order: 0)
        exercise.sets = (0..<4).map { index in
            let state: SetState
            switch day {
            case .complete:
                state = .logged
            case .partial:
                state = index < 2 ? .logged : .pending // two settled of four → half-risen
            case .available, .current, .unavailable:
                state = .pending
            }
            return ExerciseSet(index: index, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: nil, state: state)
        }
        session.exercises = [exercise]
        return session
    }
}

@MainActor
private enum BlockGridFixtureRetainer {
    private static var retained: [AnyObject] = []

    static func retain(_ object: AnyObject) {
        retained.append(object)
    }
}
