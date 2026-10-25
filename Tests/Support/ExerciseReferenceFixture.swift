import Foundation

@testable import WorkoutTracker

// Most tests address a Session that names each Exercise once, so these short forms name the first
// Exercise of `exerciseName`. A test about a repeated name passes an `ExerciseReference` itself.

extension ExerciseReference {
    static func first(_ name: ExerciseName) -> ExerciseReference {
        .unchecked(name: name, ordinal: 0)
    }
}

extension SheetWriteRequest {
    init(
        session: SessionCoordinate,
        exerciseName: String,
        setIndex: Int,
        column: PendingWriteColumn,
        operation: PendingWriteOperation,
        valueToWrite: String?,
        expectedCurrentValue: String
    ) {
        self.init(
            session: session,
            exercise: .first(ExerciseName(entered: exerciseName)),
            setIndex: setIndex,
            column: column,
            operation: operation,
            valueToWrite: valueToWrite,
            expectedCurrentValue: expectedCurrentValue
        )
    }
}

extension PendingWrite {
    convenience init(
        id: UUID = UUID(),
        // The production initializer's own default: a test that passes no createdAt queues the
        // write now, as it did before this overload existed. #689 keeps that default (wontfix).
        // swiftlint:disable:next fixture_dates_are_literal
        createdAt: Date = Date(),
        session: SessionCoordinate,
        dayNumbering: DayNumbering,
        exerciseName: String,
        setIndex: Int,
        column: PendingWriteColumn,
        operation: PendingWriteOperation,
        valueToWrite: String?,
        expectedCurrentValue: String
    ) {
        self.init(
            id: id,
            createdAt: createdAt,
            session: session,
            dayNumbering: dayNumbering,
            exercise: .first(ExerciseName(entered: exerciseName)),
            setIndex: setIndex,
            column: column,
            operation: operation,
            valueToWrite: valueToWrite,
            expectedCurrentValue: expectedCurrentValue
        )
    }
}
