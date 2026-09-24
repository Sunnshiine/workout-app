import SwiftUI
import Testing
import UIKit

@testable import WorkoutTracker

/// The `session` fixture's first Session with a rest running, in an iPhone 17 Pro window (402x874,
/// safe area 62 top and 34 bottom), under each height of sync banner (#599). Frames are global and
/// rounded to whole points.
@MainActor
@Suite
struct SessionStageLayoutTests {
    @Test func theExerciseStageFitsTheSafeAreaUnderEachBanner() throws {
        let noBanner = try SessionPageHost.layout(.exercise, banner: .outcome(.clear))
        #expect(
            noBanner
                == PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 778),
                    name: CGRect(x: 16, y: 133, width: 173, height: 41),
                    card: CGRect(x: 16, y: 418, width: 370, height: 308)
                )
        )
        let oneLine = try SessionPageHost.layout(.exercise, banner: .outcome(.writesQueued(1)))
        #expect(
            oneLine
                == PageFrames(
                    banner: CGRect(x: 16, y: 70, width: 370, height: 34),
                    stage: CGRect(x: 0, y: 104, width: 402, height: 736),
                    name: CGRect(x: 16, y: 175, width: 173, height: 41),
                    card: CGRect(x: 16, y: 418, width: 370, height: 308)
                )
        )
        let twoLines = try SessionPageHost.layout(.exercise, banner: .twoLineHeightStandIn)
        #expect(
            twoLines
                == PageFrames(
                    banner: CGRect(x: 16, y: 70, width: 370, height: 55),
                    stage: CGRect(x: 0, y: 125, width: 402, height: 715),
                    name: CGRect(x: 16, y: 196, width: 173, height: 41),
                    card: CGRect(x: 16, y: 418, width: 370, height: 308)
                )
        )
    }

    @Test func theSupersetStageFitsTheSafeAreaUnderEachBanner() throws {
        let noBanner = try SessionPageHost.layout(.superset, banner: .outcome(.clear))
        #expect(
            noBanner
                == PageFrames(
                    banner: nil,
                    stage: CGRect(x: 0, y: 62, width: 402, height: 778),
                    name: CGRect(x: 16, y: 133, width: 173, height: 41),
                    card: CGRect(x: 16, y: 418, width: 370, height: 308)
                )
        )
        let oneLine = try SessionPageHost.layout(.superset, banner: .outcome(.writesQueued(1)))
        #expect(
            oneLine
                == PageFrames(
                    banner: CGRect(x: 16, y: 70, width: 370, height: 34),
                    stage: CGRect(x: 0, y: 104, width: 402, height: 736),
                    name: CGRect(x: 16, y: 175, width: 173, height: 41),
                    card: CGRect(x: 16, y: 418, width: 370, height: 308)
                )
        )
        let twoLines = try SessionPageHost.layout(.superset, banner: .twoLineHeightStandIn)
        #expect(
            twoLines
                == PageFrames(
                    banner: CGRect(x: 16, y: 70, width: 370, height: 55),
                    stage: CGRect(x: 0, y: 125, width: 402, height: 715),
                    name: CGRect(x: 16, y: 196, width: 173, height: 41),
                    card: CGRect(x: 16, y: 418, width: 370, height: 308)
                )
        )
    }

    @Test func thePageAbsorbsABannerWithDetailWithoutMovingTheCard() throws {
        let withDetail = try SessionPageHost.layout(.exercise, banner: .detailHeightStandIn)
        #expect(
            withDetail
                == PageFrames(
                    banner: CGRect(x: 16, y: 70, width: 370, height: 76),
                    stage: CGRect(x: 0, y: 146, width: 402, height: 694),
                    name: CGRect(x: 16, y: 217, width: 173, height: 41),
                    card: CGRect(x: 16, y: 418, width: 370, height: 308)
                )
        )
    }
}

private enum StageKind {
    case exercise
    /// Back Squat paired with BB RDL, the focus on Back Squat.
    case superset
}

/// No banner `text` wraps at this width, so the taller banners are stand-ins of the capsule's
/// height: two lines of `text` (55, measured on device in #599), and those two with a `detail` line
/// under them.
private enum BannerSlot {
    case outcome(SyncOutcome)
    case twoLineHeightStandIn
    case detailHeightStandIn
}

private struct PageFrames: Equatable, CustomStringConvertible {
    let banner: CGRect?
    let stage: CGRect?
    let name: CGRect?
    let card: CGRect?

    init(banner: CGRect?, stage: CGRect?, name: CGRect?, card: CGRect?) {
        self.banner = banner.map(Self.rounded)
        self.stage = stage.map(Self.rounded)
        self.name = name.map(Self.rounded)
        self.card = card.map(Self.rounded)
    }

    var description: String {
        [("banner", banner), ("stage", stage), ("name", name), ("card", card)]
            .map { label, frame in "\(label) \(frame.map(Self.describe) ?? "none")" }
            .joined(separator: ", ")
    }

    private static func rounded(_ frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX.rounded(),
            y: frame.minY.rounded(),
            width: frame.width.rounded(),
            height: frame.height.rounded()
        )
    }

    private static func describe(_ frame: CGRect) -> String {
        "\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))"
    }
}

@MainActor
private final class FrameProbe {
    var stage: CGRect?
}

/// `SessionView`'s arrangement: the banner slot 8pt under the safe top, then the real stage with a
/// stand-in for the 43pt HUD above it and the real rest pill slot below it.
private struct SessionPage: View {
    let session: Session
    let coordinator: SessionCoordinator
    let restTimer: RestTimer
    let banner: BannerSlot
    let probe: FrameProbe

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                bannerSlot
                    .padding(.top, 8)

                SessionStageView(
                    session: session,
                    coordinator: coordinator,
                    composition: .reading,
                    actions: .inert,
                    onTopContentOffsetChange: { _ in }
                )
                .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 43) }
                .restPillInset(restTimer, composition: .reading)
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: {
                    probe.stage = $0
                }
            }
        }
    }

    @ViewBuilder
    private var bannerSlot: some View {
        switch banner {
        case .outcome(let outcome):
            SyncStatusBanner(outcome: outcome, isSyncing: false)
        case .twoLineHeightStandIn:
            standIn(height: 55)
        case .detailHeightStandIn:
            standIn(height: 76)
        }
    }

    private func standIn(height: CGFloat) -> some View {
        Color.clear
            .frame(height: height)
            .accessibilityElement()
            .accessibilityLabel("Sync status: stand-in")
            .padding(.horizontal)
    }
}

@MainActor
private enum SessionPageHost {
    private static var retainedScenarios: [ConfiguredAppScenario] = []

    static func layout(_ stage: StageKind, banner: BannerSlot) throws -> PageFrames {
        let scenario = try WorkoutScenarios.freshConfiguredApp()
        retainedScenarios.append(scenario)
        let lastPerformedLookup = LastPerformedLookupStore(context: scenario.context)
        try lastPerformedLookup.ingest(WorkoutFixtureScenarios.backSquatHistory())
        let session = try #require(scenario.store.viewedSession)
        let coordinator = SessionCoordinator(session: session)
        if stage == .superset {
            let exercises = session.exercises.sorted { $0.order < $1.order }
            try #require(coordinator.createSuperset(from: exercises[0], to: exercises[1], in: session))
        }
        let restTimer = RestTimer()
        restTimer.start(duration: 150, origin: ActiveSetID(exerciseOrder: 0, setIndex: 0), kind: .standard)

        let probe = FrameProbe()
        let page = SessionPage(
            session: session,
            coordinator: coordinator,
            restTimer: restTimer,
            banner: banner,
            probe: probe
        )
        .environment(scenario.store)
        .environment(lastPerformedLookup)
        .environment(
            ExerciseHistoryFill(client: InertSheetsClient(), context: scenario.context, index: lastPerformedLookup)
        )
        .environment(\.themePalette, Theme.palette(for: .day))
        .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
        .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)

        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        return try asAccessibilityClient {
            let controller = UIHostingController(rootView: page)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            window.rootViewController = controller
            window.isHidden = false
            defer { window.isHidden = true }

            try #require(window.safeAreaInsets == UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0))
            window.layoutIfNeeded()
            #expect(!controller.view.layer.needsLayout(), "the page settles in one layout")

            return PageFrames(
                banner: window.accessibilityFrame { $0.accessibilityLabel?.hasPrefix("Sync status:") == true },
                stage: probe.stage,
                name: window.accessibilityFrame { $0.accessibilityIdentifier == "stage-exercise-name" },
                card: window.accessibilityFrame { $0.accessibilityIdentifier == "active-set-card" }
            )
        }
    }

    /// SwiftUI builds its accessibility tree only for an accessibility client. This makes the test
    /// process one for the length of `body`, as XCUITest does for the app it drives, then puts the
    /// simulator-wide flag back.
    private static func asAccessibilityClient<Result>(_ body: () throws -> Result) throws -> Result {
        let library = try #require(dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW))
        let isEnabled = unsafeBitCast(
            try #require(dlsym(library, "_AXSAutomationEnabled")),
            to: (@convention(c) () -> Bool).self
        )
        let setEnabled = unsafeBitCast(
            try #require(dlsym(library, "_AXSSetAutomationEnabled")),
            to: (@convention(c) (Bool) -> Void).self
        )
        let wasEnabled = isEnabled()
        setEnabled(true)
        defer { setEnabled(wasEnabled) }
        return try body()
    }
}

extension SessionStageActions {
    fileprivate static var inert: SessionStageActions {
        SessionStageActions(
            focus: { _ in },
            log: { _, _ in },
            updateLoggedSet: { _, _ in },
            skip: { _ in },
            delete: { _ in },
            focusSupersetExercise: { _ in },
            dismissSuperset: { _ in },
            showSourceSession: { _ in },
            moveOn: {}
        )
    }
}

extension NSObject {
    /// The frame VoiceOver and the UI tests read for the first element that `matches`.
    fileprivate func accessibilityFrame(where matches: (NSObject) -> Bool) -> CGRect? {
        if matches(self) {
            return accessibilityFrame
        }
        for child in accessibilityChildren {
            if let frame = child.accessibilityFrame(where: matches) {
                return frame
            }
        }
        return nil
    }

    fileprivate var accessibilityIdentifier: String? {
        let isIdentifiable = responds(to: #selector(getter: UIAccessibilityIdentification.accessibilityIdentifier))
        return isIdentifiable ? value(forKey: "accessibilityIdentifier") as? String : nil
    }

    private var accessibilityChildren: [NSObject] {
        let elements = accessibilityElements?.compactMap { $0 as? NSObject } ?? []
        let subviews = (self as? UIView)?.subviews ?? []
        return elements + subviews
    }
}

private actor InertSheetsClient: SheetsClient {
    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        []
    }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        SheetSnapshot(values: [], rowVisibility: [:])
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}
}
