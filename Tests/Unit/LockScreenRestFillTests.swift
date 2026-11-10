import Foundation
import Testing

@testable import WorkoutTracker

#if os(iOS)
    @Suite
    struct LockScreenRestFillTests {
        private static let restStart = Date(timeIntervalSinceReferenceDate: 800_000_000)
        private static let restEnd = restStart.addingTimeInterval(120)

        @Test func theWholeRestRunsFromItsStartNotFromNow() {
            #expect(state(restStart: Self.restStart, restEnd: Self.restEnd).wholeRestInterval == Self.restStart...Self.restEnd)
        }

        @Test func noRestDrawsNoFill() {
            #expect(state(restStart: nil, restEnd: nil).wholeRestInterval == nil)
            #expect(state(restStart: nil, restEnd: Self.restEnd).wholeRestInterval == nil)
        }

        @Test func aRestWithNoLengthDrawsNoFill() {
            #expect(state(restStart: Self.restEnd, restEnd: Self.restEnd).wholeRestInterval == nil)
            #expect(state(restStart: Self.restEnd, restEnd: Self.restStart).wholeRestInterval == nil)
        }

        private func state(restStart: Date?, restEnd: Date?) -> WorkoutActivityAttributes.ContentState {
            WorkoutActivityAttributes.ContentState(
                exerciseName: "Back Squat",
                prescribedReps: "5",
                prescribedLoad: "RPE7",
                weightValue: "252.5",
                weightUnit: "lbs",
                setsDone: 1,
                setsTotal: 3,
                variant: .restTimerSetsLeft,
                appearance: .dark,
                restStartDate: restStart,
                restEndDate: restEnd,
                dictation: nil,
                loggablePress: .needsApp,
                face: .rest,
                stats: [],
                cadence: nil,
                coachNote: nil,
                start: nil,
                pendingWrites: 0
            )
        }
    }
#endif
