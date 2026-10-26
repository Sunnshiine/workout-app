import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

/// Counts the writes an observer of one store read hears. Each `listen` replaces the last, so a
/// read whose dependencies moved is counted through the new ones only.
@MainActor
private final class Heard {
    private(set) var notifications = 0
    private var generation = 0

    func listen(_ read: () -> Void) {
        generation += 1
        let listening = generation
        withObservationTracking(read) {
            MainActor.assumeIsolated {
                guard self.generation == listening else { return }
                self.generation += 1
                self.notifications += 1
            }
        }
    }
}

private enum StoreRead: String, CaseIterable, CustomTestStringConvertible {
    case viewedSession
    case liveEdge
    case moveOnCelebrationSession
    case currentSession
    case sessionScreen

    var testDescription: String { rawValue }

    /// `sessionScreen` is what `SessionView.body` reads from the store.
    @MainActor
    func read(_ store: WorkoutStore) {
        switch self {
        case .viewedSession: _ = store.viewedSession
        case .liveEdge: _ = store.liveEdge
        case .moveOnCelebrationSession: _ = store.moveOnCelebrationSession
        case .currentSession: _ = store.currentSession
        case .sessionScreen:
            _ = store.viewedSession
            _ = store.isViewingLiveEdge
            _ = store.moveOnCelebrationSession?.persistentModelID
            _ = store.block
            _ = store.currentSession
            _ = store.pendingBlockOverviewRequest
        }
    }
}

private enum Standing: String, CaseIterable, CustomTestStringConvertible {
    case atTheLiveEdge
    case browsedToAnEarlierSession
    case celebrating

    var testDescription: String { rawValue }

    /// Puts the store in this standing and returns the Set the 20 logs write, chosen so no log
    /// moves the Current Session.
    @MainActor
    func arrange(_ store: WorkoutStore) throws -> ExerciseSet {
        let sessions = try #require(store.block?.weeks.first?.sessions)
        func firstSet(ofDay day: Int) throws -> ExerciseSet {
            try #require(sessions.first { $0.dayNumber == day }?.exercises.first?.sets.first)
        }
        switch self {
        case .atTheLiveEdge:
            return try firstSet(ofDay: 1)
        case .browsedToAnEarlierSession:
            try store.log(try firstSet(ofDay: 3), as: SetLog(weight: .pounds(185), reps: 5, rpe: .eight))
            store.show(SessionAddress(week: 1, day: 1))
            return try firstSet(ofDay: 1)
        case .celebrating:
            store.requestMoveOnCelebration()
            return try firstSet(ofDay: 1)
        }
    }
}

private enum Storage: String, CaseIterable, CustomTestStringConvertible {
    case inMemory
    case onDisk

    var testDescription: String { rawValue }

    @MainActor
    func withStore(_ body: (WorkoutStore) throws -> Void) async throws {
        switch self {
        case .inMemory:
            let fixture = try makeStore()
            try withExtendedLifetime(fixture.container) { try body(fixture.store) }
        case .onDisk:
            try await withOnDiskStore(weekCount: 1) { store, _ in try body(store) }
        }
    }
}

@MainActor
@Test(arguments: Storage.allCases, Standing.allCases)
private func twentyLogsThatLeaveTheCurrentSessionInPlaceNotifyNoStoreObserver(_ storage: Storage, _ standing: Standing) async throws {
    try await storage.withStore { store in
        let set = try standing.arrange(store)
        let current = store.currentSession
        let heard = StoreRead.allCases.map { _ in Heard() }

        for pounds in 100..<120 {
            for (read, ears) in zip(StoreRead.allCases, heard) { ears.listen { read.read(store) } }
            try store.log(set, as: SetLog(weight: .pounds(Double(pounds)), reps: 5, rpe: .eight))
        }

        #expect(store.currentSession === current)
        for (read, ears) in zip(StoreRead.allCases, heard) {
            #expect(ears.notifications == 0, "\(read.rawValue)")
        }

        for (read, ears) in zip(StoreRead.allCases, heard) { ears.listen { read.read(store) } }
        if standing == .celebrating { store.dismissMoveOnCelebration() } else { store.moveOn() }
        let movedOn = StoreRead.allCases.map { $0 != .moveOnCelebrationSession || standing == .celebrating ? 1 : 0 }
        #expect(heard.map(\.notifications) == movedOn)
    }
}

@MainActor
@Test(arguments: Storage.allCases, Standing.allCases)
private func aReloadThatChangesNothingNotifiesNoStoreObserver(_ storage: Storage, _ standing: Standing) async throws {
    try await storage.withStore { store in
        _ = try standing.arrange(store)
        let heard = StoreRead.allCases.map { _ in Heard() }
        for (read, ears) in zip(StoreRead.allCases, heard) { ears.listen { read.read(store) } }

        store.reload()

        for (read, ears) in zip(StoreRead.allCases, heard) {
            #expect(ears.notifications == 0, "\(read.rawValue)")
        }
    }
}

@MainActor
@Test(arguments: Storage.allCases)
private func aLogThatMovesTheCurrentSessionReachesTheViewedSessionsObserverAtTheLiveEdge(_ storage: Storage) async throws {
    try await storage.withStore { store in
        let laterSet = try #require(
            store.block?.weeks.first?.sessions.first { $0.dayNumber == 2 }?.exercises.first?.sets.first
        )
        let heard = Heard()
        heard.listen { _ = store.viewedSession }

        try store.log(laterSet, as: SetLog(weight: .pounds(185), reps: 5, rpe: .eight))

        #expect(heard.notifications == 1)
        #expect(store.viewedSession?.dayNumber == 2)
    }
}
