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
        /// The first Set of Back Squat and of Deadlift cannot flush: each sits on a Prescription Line
        /// whose Notes cell holds the Coach Note, and the write conflicts rather than overwrite it
        /// (#942).
        case partialUpload = "partial-upload"
        /// The Block the UI fixture boots into for `-UITEST_FULL_BLOCK`: `partial-upload`'s Week 1
        /// Days 1 and 2, a Deadlift on Week 1 Day 3, and an Accessory on every other Day, so all
        /// sixteen Sessions are Available Sessions.
        case fullBlock = "full-block"

        public func workbook() -> LocalWorkbook {
            switch self {
            case .freshBlock:
                Self.freshBlock()
            case .partialUpload:
                Self.partialUpload()
            case .fullBlock:
                Self.fullBlock()
            }
        }

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
                    weekOneDaysOneAndTwo(),
                    deadlift(at: SessionAddress(week: 2, day: 1)),
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
                prescriptions: [weekOneDaysOneAndTwo(), deadlift(at: SessionAddress(week: 1, day: 3))]
                    + accessoryDays.map(accessory(at:))
            )
        }

        /// Four Weeks of four Days under Training Max 315/225/405, with `prescriptions` written into
        /// them. A Day no prescription lands in is an Unavailable Session.
        private static func fourWeekBlock(prescriptions: [[String: String]]) -> LocalWorkbook {
            var cells: [String: String] = [
                "E6": "Training Max",
                "C7": "Squat", "E7": "315",
                "C8": "Bench Press", "E8": "225",
                "C9": "Deadlift", "E9": "405"
            ]
            for part in (1...4).map(fourDayWeekHeaders) + prescriptions {
                cells.merge(part) { _, new in new }
            }
            return LocalWorkbook(
                spreadsheetId: spreadsheetId,
                title: title,
                tabs: [blockTab: LocalWorkbook.Tab(rows: 110, cols: 60, cells: cells)]
            )
        }

        /// Week `week`'s `Day 1` to `Day 4` headers, their date cells, and their role headers. A Day
        /// with no prescription rows under its headers is an Unavailable Session.
        private static func fourDayWeekHeaders(week: Int) -> [String: String] {
            let headerRow = headerRow(week: week)
            var cells: [String: String] = [:]
            for (index, start) in dayStartColumns.enumerated() {
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

        private static func weekOneDaysOneAndTwo() -> [String: String] {
            let (day1, day2) = (dayStartColumns[0], dayStartColumns[1])
            // Back Squat varies its `%1RM` per Set, and a `%1RM` cell prescribes every Set of its
            // Line, so each Set is its own Prescription Line.
            let lines = [
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
                ),
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
            ]
            return merged(lines)
        }

        /// A Deadlift of two Prescription Lines, one per `%1RM`.
        private static func deadlift(at address: SessionAddress) -> [String: String] {
            let (row, dayStart) = (firstPrescriptionRow(of: address), dayStartColumns[address.day - 1])
            return merged([
                prescription(
                    row: row,
                    dayStart: dayStart,
                    name: "Deadlift",
                    sets: 1,
                    reps: "3",
                    percentOneRM: "75%",
                    load: "RPE6",
                    notes: "Pull fast from the floor."
                ),
                prescription(row: row + 1, dayStart: dayStart, name: nil, sets: 1, reps: "3", percentOneRM: "80%", load: "RPE7")
            ])
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
