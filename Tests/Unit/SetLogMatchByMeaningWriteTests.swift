import Foundation
import Testing

@testable import WorkoutTracker

/// A coach may type a Set Log in any spelling the parser accepts. The compare-and-set check
/// (ADR-0003) matches a structured Set Log by its weight, reps, and RPE, not by its text, so the
/// athlete's next write to that Set lands instead of conflicting (#685).
struct SetLogMatchByMeaningWriteTests {
    private let planner = SheetWritePlanner()

    /// Comp SQ line 1 is one Set that owns J15 outright; line 2 is two Sets sharing J16 as a list.
    private func grid(j15: String = "", j16: String = "") -> SheetGrid {
        gridFromA1(
            [
                "C12": "Day 1",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "J14": "Notes",
                "C15": "Comp SQ", "D15": "1", "F15": "5", "J15": j15,
                "D16": "2", "F16": "7", "J16": j16,
                "C17": "Hip Thrust", "D17": "2"
            ],
            rows: 26,
            cols: 30
        )
    }

    private func request(setIndex: Int, expecting expected: String, writing value: String) -> SheetWriteRequest {
        SheetWriteRequest(
            session: SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 1)),
            exerciseName: "Comp SQ",
            setIndex: setIndex,
            column: .notes,
            operation: .upsert,
            valueToWrite: value,
            expectedCurrentValue: expected
        )
    }

    @Test(arguments: ["185.0x5@8", "185 x 5 @ 8", "185x5@8.0"])
    func coachSpellingOfTheExpectedSetLogLands(cell: String) throws {
        let update = try planner.plan(
            request(setIndex: 0, expecting: "185x5@8", writing: "190x5@8"),
            in: grid(j15: cell)
        )

        #expect(update.row == 14)
        #expect(update.col == 9)
        #expect(update.value == "190x5@8")
    }

    @Test func coachSpellingOfASkipLands() throws {
        let update = try planner.plan(
            request(setIndex: 0, expecting: "skip", writing: "190x5@8"),
            in: grid(j15: "SKIP")
        )

        #expect(update.value == "190x5@8")
    }

    @Test func coachSpellingInsideAListReplacesOnlyThatToken() throws {
        let update = try planner.plan(
            request(setIndex: 2, expecting: "140x7@9", writing: "145x7@9"),
            in: grid(j16: "140.0x7@9, 140 x 7 @ 9")
        )

        #expect(update.row == 15)
        #expect(update.value == "140.0x7@9, 145x7@9")
    }

    @Test func aDifferentSetLogIsStillRefused() {
        #expect(throws: SheetWriterError.unexpectedCurrentValue(expected: "185x5@8", actual: "190x5@8")) {
            try planner.plan(request(setIndex: 0, expecting: "185x5@8", writing: "195x5@8"), in: grid(j15: "190x5@8"))
        }
    }

    @Test func aDifferentSetLogInsideAListIsStillRefused() {
        #expect(throws: SheetWriterError.unexpectedCurrentValue(expected: "140x7@9", actual: "140x7@9.5")) {
            try planner.plan(
                request(setIndex: 2, expecting: "140x7@9", writing: "145x7@9"),
                in: grid(j16: "140x7@9, 140x7@9.5")
            )
        }
    }

    @Test func aDifferentSpellingOfAnotherSetLogIsStillRefused() {
        #expect(throws: SheetWriterError.unexpectedCurrentValue(expected: "185x5@8", actual: "185 x 6 @ 8")) {
            try planner.plan(
                request(setIndex: 0, expecting: "185x5@8", writing: "190x5@8"),
                in: grid(j15: "185 x 6 @ 8")
            )
        }
    }

    @Test func unstructuredSetLogStillComparesByText() {
        #expect(throws: SheetWriterError.unexpectedCurrentValue(expected: "felt heavy", actual: "felt  heavy")) {
            try planner.plan(
                request(setIndex: 0, expecting: "felt heavy", writing: "190x5@8"),
                in: grid(j15: "felt  heavy")
            )
        }
    }
}
