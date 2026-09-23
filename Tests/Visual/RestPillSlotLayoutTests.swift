import Foundation
import SwiftUI
import Testing
import UIKit

@testable import WorkoutTracker

@MainActor
@Suite
struct RestPillSlotLayoutTests {
    @Test func restPillRoomSurvivesAKeyboardUpLogUntilTheEditEnds() throws {
        let restTimer = RestTimer()
        let stage = SlotStage()
        let host = try SlotHost(restTimer: restTimer, stage: stage)
        defer { host.close() }

        stage.composition = .editingWeight
        #expect(host.laidOutSlotHeight() == 0, "an edit opened with no rest holds no room")

        restTimer.start(duration: 150, origin: ActiveSetID(exerciseOrder: 0, setIndex: 0), kind: .standard)
        #expect(host.laidOutSlotHeight() == 58, "the keyboard-up Log starts the rest under the open edit")

        stage.composition = .reading
        #expect(host.laidOutSlotHeight() == 58, "the edit ends and the pill stays")

        stage.composition = .editingWeight
        #expect(host.laidOutSlotHeight() == 58, "the next edit opens above the running rest")

        restTimer.dismiss()
        #expect(host.laidOutSlotHeight() == 58, "the rest ends mid-edit and its room stays")

        stage.composition = .reading
        #expect(host.laidOutSlotHeight() == 0, "the edit ends and the room goes")

        stage.composition = .editingWeight
        #expect(host.laidOutSlotHeight() == 0, "an edit opened after the room went holds none")
    }
}

@MainActor
@Observable
private final class SlotStage {
    var composition = SessionStageComposition.reading
    var pass = 0
    @ObservationIgnored var laidOut: StageLayout?
}

private struct StageLayout: Equatable {
    let pass: Int
    let slotHeight: CGFloat
}

private struct SlotStageView: View {
    let restTimer: RestTimer
    let stage: SlotStage

    var body: some View {
        let pass = stage.pass
        Color.clear
            .onGeometryChange(for: StageLayout.self) { proxy in
                StageLayout(pass: pass, slotHeight: proxy.safeAreaInsets.bottom)
            } action: { layout in
                stage.laidOut = layout
            }
            .restPillInset(restTimer, composition: stage.composition)
    }
}

@MainActor
private final class SlotHost {
    private let window: UIWindow
    private let controller: UIHostingController<SlotStageView>
    private let stage: SlotStage

    init(restTimer: RestTimer, stage: SlotStage) throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        controller = UIHostingController(rootView: SlotStageView(restTimer: restTimer, stage: stage))
        controller.safeAreaRegions = []
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = controller
        window.isHidden = false
        self.stage = stage
    }

    func laidOutSlotHeight() -> CGFloat? {
        stage.pass += 1
        window.layoutIfNeeded()
        guard let laidOut = stage.laidOut, laidOut.pass == stage.pass, !controller.view.layer.needsLayout() else {
            Issue.record("the stage did not settle in one layout for pass \(stage.pass)")
            return nil
        }
        return laidOut.slotHeight
    }

    func close() {
        window.isHidden = true
    }
}
