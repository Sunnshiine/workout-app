#if OFFLINE_SHEET
    import Foundation

    extension WorkbookScenario {
        public func workbook() -> LocalWorkbook {
            guard let build = Self.builders[self] else {
                preconditionFailure("\(rawValue) has no workbook builder")
            }
            return build()
        }

        /// One builder per scenario. A table has no compiler exhaustiveness check, so
        /// `everyScenarioParsesCleanlyWithAnAvailableSession` in `Tests/Unit/WorkbookScenarioTests.swift`,
        /// which builds every case, is what keeps a new scenario from shipping without a row.
        private static let builders: [Self: @Sendable () -> LocalWorkbook] = [
            .freshBlock: freshBlock,
            .partialUpload: partialUpload,
            .fullBlock: fullBlock,
            .currentSessionWithPendingSets: { block(daysPerWeek: [1], prescriptions: [weekOneDayOne()]) },
            .partiallyLoggedSession: {
                block(
                    daysPerWeek: [1],
                    prescriptions: [twoLineLift(.backSquat, at: SessionAddress(week: 1, day: 1), firstLineLogs: "235x5@6")]
                )
            },
            .openExercises: {
                block(
                    daysPerWeek: [3],
                    prescriptions: [
                        twoLineLift(.backSquat, at: SessionAddress(week: 1, day: 1), firstLineLogs: "235x5@6"),
                        twoLineLift(.benchPress, at: SessionAddress(week: 1, day: 2), firstLineLogs: "155x5@6"),
                        twoLineLift(.deadlift, at: SessionAddress(week: 1, day: 3), firstLineLogs: "305x3@6")
                    ]
                )
            },
            .completedOpenExercises: completedOpenExercises,
            .longSession: longSession,
            .perfectMoveOnCelebration: perfectMoveOnCelebration,
            .blockOverviewWithMixedSessionStates: blockOverviewWithMixedSessionStates,
            .worstCase: worstCase
        ]

        private static func freshBlock() -> LocalWorkbook {
            var cells: [String: String] = [
                "E6": "Training Max",
                "C7": "Squat", "E7": "365",
                "C8": "Bench Press", "E8": "245",
                "C9": "Deadlift", "E9": "455",
                "C12": "Day 1", "S12": "Day 2",
                "C13": "5/4/2026", "S13": "5/6/2026",
                "C37": "Day 1", "S37": "Day 2", "AI37": "Day 3",
                "C38": "5/11/2026", "S38": "5/13/2026", "AI38": "5/15/2026"
            ]
            func add(_ more: [String: String]) {
                cells.merge(more) { _, new in new }
            }
            for start in dayStartColumns.prefix(2) {
                add(roleHeaders(row: 14, dayStart: start))
            }
            for start in dayStartColumns.prefix(3) {
                add(roleHeaders(row: 39, dayStart: start))
            }
            let (day1, day2) = (dayStartColumns[0], dayStartColumns[1])
            for row in [15, 40] {
                add(prescription(row: row, dayStart: day1, name: "Back Squat", sets: 3, reps: "5", load: "RPE7"))
                add(
                    prescription(
                        row: row + 4,
                        dayStart: day1,
                        name: "2-3:1:0 BB RDL",
                        sets: 2,
                        reps: "8",
                        load: "RPE8",
                        notes: "Start w/ 10 sec hold"
                    )
                )
                add(prescription(row: row, dayStart: day2, name: "Bench Press", sets: 3, reps: "5", percentOneRM: "70%", load: "RPE7"))
                add(prescription(row: row + 4, dayStart: day2, name: "BW Pull Up", sets: 2, reps: "8", load: "BW"))
            }
            return LocalWorkbook(
                spreadsheetId: spreadsheetId,
                title: title,
                tabs: [blockTab: LocalWorkbook.Tab(rows: 60, cols: 60, cells: cells)]
            )
        }

        private static func partialUpload() -> LocalWorkbook {
            fourWeekBlock(
                prescriptions: [
                    weekOneDayOne(),
                    weekOneDayTwo(),
                    twoLineLift(.deadlift, at: SessionAddress(week: 2, day: 1)),
                    accessory(at: SessionAddress(week: 3, day: 1)),
                    accessory(at: SessionAddress(week: 4, day: 1))
                ]
            )
        }

        private static func fullBlock() -> LocalWorkbook {
            let accessoryDays = (1...4).flatMap { week in
                (1...4).map { SessionAddress(week: week, day: $0) }
            }
            .filter { $0.week > 1 || $0.day > 3 }
            return fourWeekBlock(
                prescriptions: [weekOneDayOne(), weekOneDayTwo(), twoLineLift(.deadlift, at: SessionAddress(week: 1, day: 3))]
                    + accessoryDays.map(accessory(at:))
            )
        }

        private static func fourWeekBlock(prescriptions: [[String: String]]) -> LocalWorkbook {
            block(daysPerWeek: [4, 4, 4, 4], prescriptions: prescriptions)
        }

        private static func weekOneDayOne() -> [String: String] {
            let day1 = dayStartColumns[0]
            // Back Squat varies its `%1RM` per Set, and a `%1RM` cell prescribes every Set of its
            // Line, so each Set is its own Prescription Line.
            return merged([
                prescription(
                    row: 15,
                    dayStart: day1,
                    name: "Back Squat",
                    sets: 1,
                    reps: "5",
                    percentOneRM: "75%",
                    load: "RPE6",
                    notes: "Brace hard off the floor, controlled descent."
                ),
                prescription(row: 16, dayStart: day1, name: nil, sets: 1, reps: "5", percentOneRM: "80%", load: "RPE7"),
                prescription(row: 17, dayStart: day1, name: nil, sets: 1, reps: "5", percentOneRM: "85%", load: "RPE8"),
                prescription(
                    row: 19,
                    dayStart: day1,
                    name: "2-3:1:0 BB RDL",
                    sets: 2,
                    reps: "8",
                    load: "Drop 17.5%",
                    notes: "Start w/ 10 sec hold, proceed to rep range."
                )
            ])
        }

        private static func weekOneDayTwo() -> [String: String] {
            let day2 = dayStartColumns[1]
            return merged([
                prescription(
                    row: 15,
                    dayStart: day2,
                    name: "Bench Press",
                    sets: 2,
                    reps: "5",
                    load: "RPE6, RPE7",
                    notes: "Pause every rep."
                ),
                prescription(row: 19, dayStart: day2, name: "Pull-Up", sets: 2, reps: "8", load: "BW", notes: "Use full range.")
            ])
        }

        /// A main lift the fixtures prescribe as two one-Set Prescription Lines, one per `%1RM`.
        struct TwoLineLift {
            let name: String
            let reps: String
            let percentsOneRM: (String, String)
            let notes: String

            static let backSquat = TwoLineLift(
                name: "Back Squat",
                reps: "5",
                percentsOneRM: ("75%", "80%"),
                notes: "Brace hard off the floor, controlled descent."
            )
            static let benchPress = TwoLineLift(name: "Bench Press", reps: "5", percentsOneRM: ("70%", "75%"), notes: "Pause every rep.")
            static let deadlift = TwoLineLift(
                name: "Deadlift",
                reps: "3",
                percentsOneRM: ("75%", "80%"),
                notes: "Pull fast from the floor."
            )
        }

        /// `lift` as the only Exercise of the Session at `address`: Lines at RPE 6 and 7. The first
        /// Line's Notes cell holds the Coach Note, so `firstLineLogs` go to the Exercise's spare row,
        /// the row under the second Line, as the app writes them (#942).
        private static func twoLineLift(
            _ lift: TwoLineLift,
            at address: SessionAddress,
            firstLineLogs: String? = nil
        ) -> [String: String] {
            let (row, dayStart) = (firstPrescriptionRow(of: address), dayStartColumns[address.day - 1])
            return merged([
                prescription(
                    row: row,
                    dayStart: dayStart,
                    name: lift.name,
                    sets: 1,
                    reps: lift.reps,
                    percentOneRM: lift.percentsOneRM.0,
                    load: "RPE6",
                    notes: lift.notes
                ),
                prescription(
                    row: row + 1,
                    dayStart: dayStart,
                    name: nil,
                    sets: 1,
                    reps: lift.reps,
                    percentOneRM: lift.percentsOneRM.1,
                    load: "RPE7"
                ),
                firstLineLogs.map { ["\(columnName(dayStart + 8))\(row + 2)": $0] } ?? [:]
            ])
        }

        /// A one-Line Exercise whose Notes cell holds its Coach Note, and the Set Logs written on the
        /// row under it.
        private struct NotedExercise {
            let name: String
            var sets = 1
            let reps: String
            var percentOneRM: String?
            let load: String
            let notes: String
            var logs: String?
        }

        private static func cells(of exercise: NotedExercise, row: Int, dayStart: Int) -> [String: String] {
            merged([
                prescription(
                    row: row,
                    dayStart: dayStart,
                    name: exercise.name,
                    sets: exercise.sets,
                    reps: exercise.reps,
                    percentOneRM: exercise.percentOneRM,
                    load: exercise.load,
                    notes: exercise.notes
                ),
                exercise.logs.map { setLogs($0, under: row, dayStart: dayStart) } ?? [:]
            ])
        }

        /// `exercise` as the only Exercise of the Session at `address`.
        private static func cells(of exercise: NotedExercise, at address: SessionAddress) -> [String: String] {
            cells(of: exercise, row: firstPrescriptionRow(of: address), dayStart: dayStartColumns[address.day - 1])
        }

        private static func completedOpenExercises() -> LocalWorkbook {
            let bench = NotedExercise(
                name: "Bench Press",
                reps: "5",
                percentOneRM: "70%",
                load: "RPE6",
                notes: "Pause every rep.",
                logs: "155x5@6"
            )
            return block(
                daysPerWeek: [3],
                prescriptions: [
                    twoLineLift(.backSquat, at: SessionAddress(week: 1, day: 1), firstLineLogs: "235x5@6"),
                    cells(of: bench, at: SessionAddress(week: 1, day: 2)),
                    twoLineLift(.deadlift, at: SessionAddress(week: 1, day: 3))
                ]
            )
        }

        private static func longSession() -> LocalWorkbook {
            let exercises = [
                NotedExercise(name: "Primer Row", reps: "8", load: "RPE6", notes: "Move crisply.", logs: "95x8@6"),
                NotedExercise(name: "Back Squat", reps: "5", load: "RPE6", notes: "Brace hard."),
                NotedExercise(name: "Bench Press", reps: "5", load: "RPE6", notes: "Pause every rep."),
                NotedExercise(name: "Chest-Supported Row", reps: "10", load: "RPE7", notes: "Pause at the top."),
                NotedExercise(name: "Split Squat", reps: "8", load: "RPE7", notes: "Keep the front foot planted."),
                NotedExercise(name: "Hamstring Curl", reps: "12", load: "RPE8", notes: "Control the eccentric."),
                NotedExercise(name: "Cable Crunch", reps: "12", load: "RPE8", notes: "Exhale hard."),
                NotedExercise(name: "Farmer Carry", reps: "40 sec", load: "RPE7", notes: "Tall posture.")
            ]
            let (first, dayStart) = (firstPrescriptionRow(of: SessionAddress(week: 1, day: 1)), dayStartColumns[0])
            // Each Exercise leaves the row under it empty, so a Coach Note's Set Logs have a Visible
            // Writable Row to move to.
            return block(
                daysPerWeek: [1],
                prescriptions: exercises.enumerated().map { cells(of: $0.element, row: first + $0.offset * 2, dayStart: dayStart) }
            )
        }

        private static func perfectMoveOnCelebration() -> LocalWorkbook {
            let squat = NotedExercise(
                name: "Back Squat",
                sets: 2,
                reps: "5",
                load: "RPE6, RPE7",
                notes: "Perfect Session fixture.",
                logs: "185x5@6, skip"
            )
            return block(daysPerWeek: [2], prescriptions: [cells(of: squat, at: SessionAddress(week: 1, day: 1))])
        }

        private static func blockOverviewWithMixedSessionStates() -> LocalWorkbook {
            let sessions: [SessionAddress: NotedExercise] = [
                SessionAddress(week: 1, day: 1): NotedExercise(
                    name: "Competition Squat",
                    sets: 2,
                    reps: "5",
                    load: "RPE7, RPE8",
                    notes: "Completed Session.",
                    logs: "185x5@7, skip"
                ),
                SessionAddress(week: 1, day: 2): NotedExercise(
                    name: "Paused Bench Press",
                    sets: 2,
                    reps: "5",
                    load: "RPE7, RPE8",
                    notes: "Has Open Exercises.",
                    logs: "155x5@7"
                ),
                SessionAddress(week: 1, day: 3): NotedExercise(
                    name: "Current Deadlift",
                    sets: 2,
                    reps: "3",
                    load: "RPE6, RPE7",
                    notes: "Current Session."
                ),
                SessionAddress(week: 2, day: 1): NotedExercise(
                    name: "Upcoming Squat",
                    sets: 2,
                    reps: "5",
                    load: "RPE6, RPE7",
                    notes: "Upcoming Session."
                )
            ]
            return block(daysPerWeek: [3, 1], prescriptions: sessions.map { cells(of: $0.value, at: $0.key) })
        }

        private static func worstCase() -> LocalWorkbook {
            let (row, day1) = (firstPrescriptionRow(of: SessionAddress(week: 1, day: 1)), dayStartColumns[0])
            let squat = NotedExercise(
                name: "2-3:1:0 Paused Low-Bar Competition Back Squat w/ Safety Squat Bar",
                sets: 8,
                reps: "AMRAP",
                percentOneRM: "87.5%",
                load: "Start conservative and work up to a heavy single",
                notes: "Belt on from the second set. If the first rep moves slower than last week, cap the top set at RPE 8"
                    + " and take the remaining sets as back-offs at 80% of it. Film the top set from the side and send it"
                    + " to me before Thursday's session.",
                logs: "1025.5x1@10, 1015x1@9.5, felt heavy belt off knees caved on rep three"
            )
            let longNamedDays = (1...4).flatMap { week in (1...4).map { SessionAddress(week: week, day: $0) } }
                .filter { ![SessionAddress(week: 1, day: 1), SessionAddress(week: 1, day: 2)].contains($0) }
            return block(
                daysPerWeek: [4, 4, 4, 4],
                prescriptions: [
                    cells(of: squat, row: row, dayStart: day1),
                    prescription(row: row + 2, dayStart: day1, name: "Dip", sets: 1, reps: "5+", load: "BW"),
                    prescription(
                        row: row + 3,
                        dayStart: day1,
                        name: "Chest-Supported Dumbbell Row (Neutral Grip, 3-Second Eccentric)",
                        sets: 2,
                        reps: "8-10",
                        load: "RPE 5.5"
                    ),
                    prescription(row: row + 4, dayStart: day1, name: nil, sets: 3, reps: "40 sec", load: "Drop 17.5%"),
                    prescription(
                        row: row + 5,
                        dayStart: day1,
                        name: "Single-Leg Romanian Deadlift to Overhead Press Complex",
                        sets: 12,
                        reps: "1",
                        load: "RPE10"
                    )
                ] + [coachEdgeCases(at: SessionAddress(week: 1, day: 2))] + longNamedDays.map(longNamedAccessory(at:))
            )
        }

        /// Cells a coach leaves half-typed: a Sets count of 0 and a blank one, a row with no Reps,
        /// Load, or RPE, a four-digit Load, and a decimal one, none with a Last Performed.
        private static func coachEdgeCases(at address: SessionAddress) -> [String: String] {
            let (row, dayStart) = (firstPrescriptionRow(of: address), dayStartColumns[address.day - 1])
            var blankSets = prescription(row: row + 1, dayStart: dayStart, name: "Cable Row", sets: 1, reps: "10", load: "50")
            blankSets.removeValue(forKey: "\(columnName(dayStart + 1))\(row + 1)")
            return merged([
                prescription(row: row, dayStart: dayStart, name: "Zero Sets Curl", sets: 0, reps: "10", load: "RPE8"),
                blankSets,
                prescription(row: row + 2, dayStart: dayStart, name: "Landmine Press", sets: 3, reps: "", load: ""),
                prescription(row: row + 3, dayStart: dayStart, name: "Rack Pull", sets: 2, reps: "1", load: "1405"),
                prescription(row: row + 4, dayStart: dayStart, name: "Close-Grip Bench Press", sets: 2, reps: "5", load: "142.5")
            ])
        }

        private static func longNamedAccessory(at address: SessionAddress) -> [String: String] {
            prescription(
                row: firstPrescriptionRow(of: address),
                dayStart: dayStartColumns[address.day - 1],
                name: "Banded Pause Bench Press with Feet Up and Two-Second Hold",
                sets: 4,
                reps: "6",
                load: "RPE7"
            )
        }

        /// The Set Logs of a one-Line Exercise whose Notes cell at `row` holds its Coach Note. They
        /// move to the Visible Writable Row under it, as the app writes them.
        private static func setLogs(_ logs: String, under row: Int, dayStart: Int) -> [String: String] {
            ["\(columnName(dayStart + 8))\(row + 1)": logs]
        }

        private static func accessory(at address: SessionAddress) -> [String: String] {
            prescription(
                row: firstPrescriptionRow(of: address),
                dayStart: dayStartColumns[address.day - 1],
                name: "Accessory",
                sets: 1,
                reps: "10",
                load: "RPE6",
                notes: "Controlled reps."
            )
        }
    }
#endif
