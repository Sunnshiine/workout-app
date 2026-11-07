import Foundation
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import WorkoutTracker

/// The Meet's pages in each stage of the day. The clock is frozen, so a window's numeral is the same
/// on every run.
@MainActor
@Suite(.snapshots(record: .never))
struct MeetVisualTests {
    private final class Clock {
        var date = Date(timeIntervalSince1970: 1_793_966_400)
    }

    private enum Page {
        case plan
        case platform
    }

    private let clock = Clock()

    private func store(_ meet: Meet?) -> MeetStore {
        let clock = clock
        let store = MeetStore(defaults: .inMemory(), now: { clock.date })
        if let meet {
            store.start(meet)
        }
        return store
    }

    private func dayStore() throws -> MeetStore {
        store(try #require(MeetDayFixture.meet()))
    }

    private func onThePlatform() throws -> MeetStore {
        let store = try dayStore()
        store.setAttemptsOut(0)
        return store
    }

    private func windowStore(secondsAfterLights: TimeInterval) throws -> MeetStore {
        let store = try onThePlatform()
        try store.mark(.good)
        clock.date.addTimeInterval(secondsAfterLights)
        return store
    }

    private func finishedStore(endsInTotal: Bool) throws -> MeetStore {
        let store = try dayStore()
        for lift in MainLift.allCases {
            store.setAttemptsOut(0)
            try store.mark(endsInTotal || lift != .bench ? .good : .noLift)
            try store.pass()
        }
        return store
    }

    private func assertPage(
        _ page: Page,
        store: MeetStore,
        appearance: Theme.Appearance,
        colorScheme: ColorScheme,
        dynamicType: DynamicTypeSize = WorkoutVisualBaseline.dynamicTypeSize,
        testName: String = #function
    ) {
        let view = NavigationStack {
            switch page {
            case .plan: MeetPlanView()
            case .platform: MeetPlatformView()
            }
        }
        .environment(store)
        .environment(\.themePalette, Theme.palette(for: appearance))
        .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
        .environment(\.dynamicTypeSize, dynamicType)
        .preferredColorScheme(colorScheme)

        assertSnapshot(
            of: view,
            as: .image(precision: WorkoutVisualBaseline.labelAntialiasingPrecision, layout: .device(config: .workoutVisualBaseline)),
            testName: testName
        )
    }

    @Test func noMeetMatchesVisualBaseline() {
        assertPage(.plan, store: store(nil), appearance: .day, colorScheme: .light)
    }

    @Test func noMeetMatchesNightVisualBaseline() {
        assertPage(.plan, store: store(nil), appearance: .night, colorScheme: .dark)
    }

    @Test func planMatchesVisualBaseline() throws {
        assertPage(.plan, store: try dayStore(), appearance: .day, colorScheme: .light)
    }

    @Test func planMatchesNightVisualBaseline() throws {
        assertPage(.plan, store: try dayStore(), appearance: .night, colorScheme: .dark)
    }

    @Test func worstCasePlanMatchesVisualBaseline() throws {
        assertPage(.plan, store: store(try #require(MeetDayFixture.worstCase())), appearance: .day, colorScheme: .light)
    }

    @Test func warmUpMatchesVisualBaseline() throws {
        assertPage(.platform, store: try dayStore(), appearance: .day, colorScheme: .light)
    }

    @Test func warmUpMatchesNightVisualBaseline() throws {
        assertPage(.platform, store: try dayStore(), appearance: .night, colorScheme: .dark)
    }

    @Test func warmUpAtLargestTypeMatchesVisualBaseline() throws {
        assertPage(.platform, store: try dayStore(), appearance: .day, colorScheme: .light, dynamicType: .xxxLarge)
    }

    @Test func onThePlatformMatchesVisualBaseline() throws {
        assertPage(.platform, store: try onThePlatform(), appearance: .day, colorScheme: .light)
    }

    @Test func onThePlatformMatchesNightVisualBaseline() throws {
        assertPage(.platform, store: try onThePlatform(), appearance: .night, colorScheme: .dark)
    }

    @Test func runningWindowMatchesVisualBaseline() throws {
        assertPage(.platform, store: try windowStore(secondsAfterLights: 20), appearance: .day, colorScheme: .light)
    }

    @Test func closingWindowMatchesVisualBaseline() throws {
        assertPage(.platform, store: try windowStore(secondsAfterLights: 50), appearance: .day, colorScheme: .light)
    }

    @Test func closingWindowMatchesNightVisualBaseline() throws {
        assertPage(.platform, store: try windowStore(secondsAfterLights: 50), appearance: .night, colorScheme: .dark)
    }

    @Test func windowWithNoCalledAttemptMatchesVisualBaseline() throws {
        let store = try dayStore()
        store.edit { $0.editLift(.squat) { $0.clear(from: .second) } }
        store.setAttemptsOut(0)
        try store.mark(.good)
        assertPage(.platform, store: store, appearance: .day, colorScheme: .light)
    }

    @Test func expiredWindowMatchesVisualBaseline() throws {
        assertPage(.platform, store: try windowStore(secondsAfterLights: 70), appearance: .day, colorScheme: .light)
    }

    @Test func expiredWindowMatchesNightVisualBaseline() throws {
        assertPage(.platform, store: try windowStore(secondsAfterLights: 70), appearance: .night, colorScheme: .dark)
    }

    @Test func finishedMatchesVisualBaseline() throws {
        assertPage(.platform, store: try finishedStore(endsInTotal: true), appearance: .day, colorScheme: .light)
    }

    @Test func finishedMatchesNightVisualBaseline() throws {
        assertPage(.platform, store: try finishedStore(endsInTotal: true), appearance: .night, colorScheme: .dark)
    }

    @Test func finishedWithNoTotalMatchesVisualBaseline() throws {
        assertPage(.platform, store: try finishedStore(endsInTotal: false), appearance: .day, colorScheme: .light)
    }
}
