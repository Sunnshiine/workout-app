import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

/// Runs `body` with a SQLite store file in a temporary directory of its own, the shape the app's
/// store has on the device. The directory goes afterwards, and the `-wal` and `-shm` files with it.
@MainActor
func withOnDiskStoreFile<T>(_ body: (URL) async throws -> T) async throws -> T {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("workout-store-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try await body(directory.appendingPathComponent("store.sqlite"))
}

/// Records an issue for each Session `store` shows that its Block does not hold.
///
/// A sync deletes the Block and inserts the re-parsed one, so a Session held across it belongs to
/// no Block. Whether that Session still reads its Week depends on the order SwiftData ran the
/// cascade delete in, which changes from run to run, in memory and on disk alike (#1001). A test
/// that reads the held Session's address therefore catches the hold only some of the time; this
/// check catches it every time.
@MainActor
func expectShowsOnlySessionsOfItsBlock(_ store: WorkoutStore, sourceLocation: SourceLocation = #_sourceLocation) {
    let held = Set(store.block?.weeks.flatMap(\.sessions).map(\.persistentModelID) ?? [])
    let shown = [
        ("viewedSession", store.viewedSession),
        ("currentSession", store.currentSession),
        ("moveOnCelebrationSession", store.moveOnCelebrationSession)
    ]
    for case let (name, session?) in shown {
        #expect(held.contains(session.persistentModelID), "\(name) is not a Session of the Block", sourceLocation: sourceLocation)
    }
}
