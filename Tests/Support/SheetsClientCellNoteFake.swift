@testable import WorkoutTracker

struct FakeModelsNoCellNotes: Error {}

/// A fake that does not model Cell Notes turns one down, so a test that reaches it fails instead of
/// passing on a write that went nowhere. Living here rather than in `Sources/` is what makes each
/// real client write its own.
extension SheetsClient {
    func writeCellNote(_ note: SheetCellNoteWrite, spreadsheetId: String) async throws {
        throw FakeModelsNoCellNotes()
    }
}
