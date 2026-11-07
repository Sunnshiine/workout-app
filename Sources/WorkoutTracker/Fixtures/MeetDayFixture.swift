#if DEBUG
    import Foundation

    /// The date is a literal, so the count of days on the Plan moves with the wall clock, and the day
    /// itself does not depend on it.
    enum MeetDayFixture {
        static let date = MeetDate(year: 2026, month: 12, day: 5)

        static func meet() -> Meet? {
            guard let date else { return nil }
            var meet = Meet(date: date, federation: .ipf)
            meet.liftersInFlight = 10
            enter(&meet, .squat, attempts: [18000, 19000, 19750], rack: "14, racks in", steps: squatSteps)
            enter(&meet, .bench, attempts: [11000, 11750, 12250], rack: "8, safety 4, blocks", steps: benchSteps)
            enter(&meet, .deadlift, attempts: [20500, 21500, 22750], rack: "", steps: deadliftSteps)
            return meet
        }

        static func worstCase() -> Meet? {
            guard let date else { return nil }
            var meet = Meet(date: date, federation: .usapl)
            meet.liftersInFlight = 14
            enter(
                &meet,
                .squat,
                attempts: [50550, 51000, 52050],
                rack: "17, racks out, one notch down on the left because the pins stick, safeties 12",
                steps: squatSteps
            )
            enter(
                &meet,
                .bench,
                attempts: [33250, 34000, 35550],
                rack: "12, safety 9, blocks, feet up on the second board",
                steps: benchSteps
            )
            enter(&meet, .deadlift, attempts: [45000], rack: "", steps: [])
            return meet
        }

        private static func enter(_ meet: inout Meet, _ lift: MainLift, attempts: [Int], rack: String, steps: [WarmupRoomStep]) {
            meet.editLift(lift) { edit in
                for (index, hundredths) in attempts.enumerated() {
                    edit.enter(Kilograms(hundredths: hundredths), at: AttemptOrdinal(rawValue: index) ?? .third)
                }
                edit.rackHeights = rack
                edit.setWarmupRoomPlan(steps)
            }
        }

        private static func step(_ hundredths: Int, _ reps: Int, _ attemptsOut: Int) -> WarmupRoomStep {
            WarmupRoomStep(kilograms: Kilograms(hundredths: hundredths), reps: reps, attemptsOut: attemptsOut)
        }

        private static let squatSteps = [
            step(6000, 5, 18), step(10000, 3, 14), step(13000, 2, 10), step(15000, 1, 6), step(16500, 1, 3)
        ]
        private static let benchSteps = [
            step(4000, 5, 15), step(7000, 3, 11), step(9000, 2, 7), step(10000, 1, 3)
        ]
        private static let deadliftSteps = [
            step(7000, 5, 18), step(12000, 3, 14), step(15000, 2, 10), step(17500, 1, 6), step(19000, 1, 3)
        ]
    }
#endif
