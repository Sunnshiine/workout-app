#if DEBUG
    import Foundation

    enum WorkoutFixtureScenarios {
        static let sheetId = "FIXTURE"
        static let replacementSheetId = "REPLACEMENT"
        static let blockTab = "Block 27"

        static let replacementSheetGrid = gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2", "AI12": "Day 3", "AX12": "Day 4",
                "C13": "5/1/2026",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
                "C15": "Replacement Squat", "D15": "1", "F15": "5", "H15": "RPE8"
            ],
            rows: 20,
            cols: 60
        )

        /// The spreadsheet the onboarding and Settings pickers offer in place of the fixture's own.
        static let replacementWorkbook = LocalWorkbook(
            spreadsheetId: replacementSheetId,
            title: "Replacement Training Log",
            snapshots: [blockTab: SheetSnapshot(values: replacementSheetGrid)]
        )

        static func syncFailureOutcome() -> SyncOutcome {
            .writesRefused(["Sheet write failed"])
        }

        static func queuedWrite() -> PendingWrite {
            PendingWrite(
                createdAt: Date(timeIntervalSinceReferenceDate: 0),
                session: SessionCoordinate(blockTab: blockTab, address: SessionAddress(week: 1, day: 1)),
                dayNumbering: .headerNumber,
                exerciseName: "Back Squat",
                setIndex: 0,
                column: .notes,
                operation: .upsert,
                valueToWrite: "185x5@8",
                expectedCurrentValue: ""
            )
        }

        static func lastPerformedBackSquat() -> LastPerformedEntry {
            LastPerformedEntry(
                exerciseName: "Back Squat",
                resultText: "245x5@6, 255x5@7",
                performedOn: Date(timeIntervalSinceReferenceDate: 100),
                source: SessionCoordinate(blockTab: "Block 26", address: SessionAddress(week: 4, day: 3)).storageValue
            )
        }

        /// Deeper Back Squat history so the Exercise History sheet has Block grouping to show. The
        /// newest entry (`lastPerformedBackSquat`) still drives the Last Performed line byte-for-byte.
        static func backSquatHistory() -> [LastPerformedEntry] {
            [
                lastPerformedBackSquat(),
                LastPerformedEntry(
                    exerciseName: "Back Squat",
                    resultText: "235x5@6, 245x5@7",
                    performedOn: Date(timeIntervalSinceReferenceDate: 60),
                    source: SessionCoordinate(blockTab: "Block 26", address: SessionAddress(week: 2, day: 3)).storageValue
                ),
                LastPerformedEntry(
                    exerciseName: "Back Squat",
                    resultText: "225x5@7",
                    performedOn: Date(timeIntervalSinceReferenceDate: 30),
                    source: SessionCoordinate(blockTab: "Block 25", address: SessionAddress(week: 3, day: 1)).storageValue
                )
            ]
        }

        static func benchPressHistory() -> [LastPerformedEntry] {
            [
                LastPerformedEntry(
                    exerciseName: "Bench Press",
                    resultText: "185x5@7, 195x5@8",
                    performedOn: Date(timeIntervalSinceReferenceDate: 90),
                    source: SessionCoordinate(blockTab: "Block 26", address: SessionAddress(week: 4, day: 1)).storageValue
                )
            ]
        }
    }
#endif
