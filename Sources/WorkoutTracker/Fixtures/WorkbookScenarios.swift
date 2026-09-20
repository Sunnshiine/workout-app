#if OFFLINE_SHEET
    import Foundation

    /// Seed workbooks in the coach's canonical layout, fed through the real parser rather than built
    /// as a SwiftData graph, so a scenario proves the whole Sheet round trip.
    public enum WorkbookScenario: String, CaseIterable, Sendable {
        /// One Block tab, two logged-nothing Weeks, and an Unavailable Day 3 in Week 2 (a Partially
        /// Uploaded Block). The Coach Note on the RDL exercises the Visible Writable Row rule.
        case freshBlock = "fresh-block"

        public func workbook() -> LocalWorkbook {
            switch self {
            case .freshBlock:
                Self.freshBlock()
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

        private static let dayStartColumns = [2, 18, 34]

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
            for start in dayStartColumns {
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
                add(prescription(row: row, dayStart: day2, name: "Bench Press", sets: 3, reps: "5", load: "RPE7"))
                add(prescription(row: row + 4, dayStart: day2, name: "BW Pull Up", sets: 2, reps: "8", load: "BW"))
            }
            return LocalWorkbook(
                spreadsheetId: spreadsheetId,
                title: title,
                tabs: [blockTab: LocalWorkbook.Tab(rows: 60, cols: 60, cells: cells)]
            )
        }

        private static func roleHeaders(row: Int, dayStart: Int) -> [String: String] {
            Dictionary(uniqueKeysWithValues: roleHeaderOffsets.map { ("\(columnName(dayStart + $0.offset))\(row)", $0.label) })
        }

        // One parameter per spreadsheet column the prescription writes. A struct here would carry
        // the same six values one call further out and name the columns twice.
        // swiftlint:disable:next function_parameter_count
        private static func prescription(
            row: Int,
            dayStart: Int,
            name: String,
            sets: Int,
            reps: String,
            load: String,
            notes: String? = nil
        ) -> [String: String] {
            var cells = [
                "\(columnName(dayStart))\(row)": name,
                "\(columnName(dayStart + 1))\(row)": String(sets),
                "\(columnName(dayStart + 3))\(row)": reps,
                "\(columnName(dayStart + 5))\(row)": load
            ]
            if let notes {
                cells["\(columnName(dayStart + 8))\(row)"] = notes
            }
            return cells
        }
    }
#endif
