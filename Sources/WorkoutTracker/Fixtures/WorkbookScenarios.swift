#if OFFLINE_SHEET
    import Foundation

    /// Seed workbooks in the coach's canonical layout, fed through the real parser rather than built
    /// as a SwiftData graph, so a scenario proves the whole Sheet round trip.
    public enum WorkbookScenario: String, CaseIterable, Sendable {
        /// One Block tab, two logged-nothing Weeks, and an Unavailable Day 3 in Week 2 (a Partially
        /// Uploaded Block). The Coach Note on the RDL exercises the Visible Writable Row rule, and
        /// Bench Press carries one `%1RM` for every Set of its Line.
        case freshBlock = "fresh-block"
        /// The Block the app's UI fixture boots into when a launch names no scenario: four Weeks of
        /// four Days, eleven of them Unavailable Sessions with no prescription rows (a Partially
        /// Uploaded Block). It carries a `%1RM` per Set on the main lifts and a Drop Load on the RDL,
        /// so both of those Load Suggestion arms are reachable from cells a coach could have typed.
        /// The first Set of Back Squat and of Deadlift each sits on a Prescription Line whose Notes
        /// cell holds the Coach Note, so its Set Log flushes to the Exercise's spare row (#942).
        case partialUpload = "partial-upload"
        /// The Block the UI fixture boots into for the Full Block scenario: `partial-upload`'s Week 1
        /// Days 1 and 2, a Deadlift on Week 1 Day 3, and an Accessory on every other Day, so all
        /// sixteen Sessions are Available Sessions.
        case fullBlock = "full-block"
        /// Week 1 Day 1's Back Squat and RDL with nothing logged, the Current Session a test of the
        /// Stage starts from.
        case currentSessionWithPendingSets = "current-session-with-pending-sets"
        /// Week 1 Day 1 alone, its Back Squat's first Set logged and its second open.
        case partiallyLoggedSession = "partially-logged-session"
        /// Three Days of Week 1, each one main lift with its first Set logged and its second open,
        /// so every Session has Open Exercises.
        case openExercises = "open-exercises"
        /// `open-exercises` with Day 2 a one-Set Bench Press, logged, so the Current Session is
        /// complete while Day 1's Back Squat is still open.
        case completedOpenExercises = "completed-open-exercises"
        /// One Session of eight one-Set Exercises, the first logged, long enough to scroll.
        case longSession = "long-session"
        /// A Back Squat with one Set logged and one skipped on Day 1, a Perfect Session, and an
        /// Unavailable Day 2 to move on to.
        case perfectMoveOnCelebration = "perfect-move-on-celebration"
        /// One Session of every status Block Overview draws: a complete Day 1, Day 2 with Open
        /// Exercises, Day 3 to train next, and Week 2 Day 1 still upcoming.
        case blockOverviewWithMixedSessionStates = "block-overview-with-mixed-session-states"

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
            .blockOverviewWithMixedSessionStates: blockOverviewWithMixedSessionStates
        ]

        static let spreadsheetId = "FIXTURE"
        static let title = "Fixture Training Log"
        static let blockTab = "Block 27"
    }

    extension WorkbookScenario {
        private static let roleHeaderOffsets: [(offset: Int, label: String)] = [
            (1, "Sets"), (3, "Reps"), (4, "%1RM"), (5, "Load"), (6, "Last set RPE"), (8, "Notes")
        ]

        private static let dayStartColumns = [2, 18, 34, 50]

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

        /// Rows between one Week's `Day N` header row and the next, as `fresh-block` lays them out.
        private static let weekRowStride = 25

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

        /// One Week per entry of `daysPerWeek`, each with that many Days, under Training Max
        /// 315/225/405, with `prescriptions` written into them. A Day no prescription lands in is an
        /// Unavailable Session.
        private static func block(daysPerWeek: [Int], prescriptions: [[String: String]]) -> LocalWorkbook {
            var cells: [String: String] = [
                "E6": "Training Max",
                "C7": "Squat", "E7": "315",
                "C8": "Bench Press", "E8": "225",
                "C9": "Deadlift", "E9": "405"
            ]
            let headers = daysPerWeek.enumerated().map { weekHeaders(week: $0.offset + 1, days: $0.element) }
            for part in headers + prescriptions {
                cells.merge(part) { _, new in new }
            }
            return LocalWorkbook(
                spreadsheetId: spreadsheetId,
                title: title,
                tabs: [blockTab: LocalWorkbook.Tab(rows: 110, cols: 60, cells: cells)]
            )
        }

        /// Week `week`'s `Day 1` to `Day <days>` headers, their date cells, and their role headers.
        /// A Day with no prescription rows under its headers is an Unavailable Session.
        private static func weekHeaders(week: Int, days: Int) -> [String: String] {
            let headerRow = headerRow(week: week)
            var cells: [String: String] = [:]
            for (index, start) in dayStartColumns.prefix(days).enumerated() {
                cells["\(columnName(start))\(headerRow)"] = "Day \(index + 1)"
                cells["\(columnName(start))\(headerRow + 1)"] = strideDate(week: week, day: index + 1)
                cells.merge(roleHeaders(row: headerRow + 2, dayStart: start)) { _, new in new }
            }
            return cells
        }

        private static func headerRow(week: Int) -> Int {
            12 + (week - 1) * weekRowStride
        }

        /// The row of a Day's first prescription: under its `Day N`, date, and role header rows.
        private static func firstPrescriptionRow(of address: SessionAddress) -> Int {
            headerRow(week: address.week) + 3
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

        private static func merged(_ parts: [[String: String]]) -> [String: String] {
            parts.reduce(into: [:]) { cells, part in cells.merge(part) { _, new in new } }
        }

        /// The Session's calendar day on a 7-day stride from 1 January 2001, the reference date, so
        /// Day `d` of Week `w` falls on day `(w - 1) * 7 + d` after it.
        private static func strideDate(week: Int, day: Int) -> String {
            "1/\(1 + (week - 1) * 7 + day)/2001"
        }

        private static func roleHeaders(row: Int, dayStart: Int) -> [String: String] {
            Dictionary(uniqueKeysWithValues: roleHeaderOffsets.map { ("\(columnName(dayStart + $0.offset))\(row)", $0.label) })
        }

        // One parameter per spreadsheet column the prescription writes. A struct here would carry
        // the same values one call further out and name the columns twice. A nil name is a
        // continuation row: another Prescription Line of the Exercise above it (ADR-0010).
        // swiftlint:disable:next function_parameter_count
        private static func prescription(
            row: Int,
            dayStart: Int,
            name: String?,
            sets: Int,
            reps: String,
            percentOneRM: String? = nil,
            load: String,
            notes: String? = nil
        ) -> [String: String] {
            var cells = [
                "\(columnName(dayStart + 1))\(row)": String(sets),
                "\(columnName(dayStart + 3))\(row)": reps,
                "\(columnName(dayStart + 5))\(row)": load
            ]
            if let name {
                cells["\(columnName(dayStart))\(row)"] = name
            }
            if let percentOneRM {
                cells["\(columnName(dayStart + 4))\(row)"] = percentOneRM
            }
            if let notes {
                cells["\(columnName(dayStart + 8))\(row)"] = notes
            }
            return cells
        }
    }

    extension WorkbookScenario {
        /// The scenario's Block tab as a sync reads it: `SheetParser.parse`, the first of the two
        /// calls `SyncCoordinator.sync` makes. Every scenario has the one tab.
        func parsedBlockTab() -> ParsedBlock {
            guard let tab = workbook().tabs[Self.blockTab] else {
                preconditionFailure("\(rawValue) has no \(Self.blockTab) tab")
            }
            return SheetParser().parse(snapshot: tab.snapshot, tabName: Self.blockTab)
        }

        /// The Block a sync of this scenario would persist: the parse, then `BlockBuilder.makeBlock`,
        /// the second call. It stops before the overlays `SyncCoordinator.replacePersistedBlock`
        /// applies, which only matter once local athlete state exists.
        @MainActor
        func block() -> Block {
            BlockBuilder.makeBlock(from: parsedBlockTab().block)
        }
    }
#endif
