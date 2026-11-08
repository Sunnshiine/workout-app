import SwiftUI
import Testing
import UIKit

@testable import WorkoutTracker

@MainActor
private final class SelectionRecorder {
    var labels: [String] = []
}

/// Under VoiceOver a rail is one adjustable element whose value is the selection and whose steps
/// move one detent (DESIGN.md §9). Without it the cells stay buttons, for Voice Control and the
/// tests that tap them.
@MainActor
struct ValueRailAccessibilityTests {
    private static let screen = CGSize(width: 402, height: 874)

    private func repsRail(readsAsOneElement: Bool, recording recorder: SelectionRecorder) -> some View {
        ValueRailControl(
            chips: RepsScalePresentation(prescribedReps: PrescribedReps("5"), selection: "5").chips,
            selectedIndex: 4,
            label: "Reps",
            isInvalid: false,
            readsAsOneElement: readsAsOneElement,
            onSelect: { recorder.labels.append($0) }
        )
        .frame(width: 163)
        .environment(\.themePalette, Theme.palette(for: .day))
    }

    /// SwiftUI rebuilds a host's accessibility tree on the run loop, and a read before that turn can
    /// still see the tree of the host before it.
    private func settledTree(of window: UIWindow) -> [NSObject] {
        CFRunLoopRunInMode(.defaultMode, 0.1, false)
        window.layoutIfNeeded()
        return window.accessibilityTree
    }

    @Test func asOneElementTheRailReadsItsSelectionAndStepsADetentEachWay() throws {
        let recorder = SelectionRecorder()

        let values = try AccessibilityHost.read(repsRail(readsAsOneElement: true, recording: recorder), in: [Self.screen]) { window in
            let rail = try #require(settledTree(of: window).first { $0.elementIdentifier == "reps-rail" })
            #expect(rail.accessibilityTraits.contains(.adjustable))
            #expect(rail.accessibilityLabel == "Reps")
            rail.accessibilityIncrement()
            rail.accessibilityDecrement()
            return rail.accessibilityValue
        }

        #expect(values == ["5"])
        #expect(recorder.labels == ["6", "4"])
    }

    @Test func asCellsEachValueStaysALabelledButtonAndNoRailElementExists() throws {
        let recorder = SelectionRecorder()

        let read = try AccessibilityHost.read(repsRail(readsAsOneElement: false, recording: recorder), in: [Self.screen]) { window in
            let tree = settledTree(of: window)
            let cell = try #require(tree.first { $0.elementIdentifier == "reps-5" })
            return (
                identifiers: tree.compactMap(\.elementIdentifier),
                label: cell.accessibilityLabel,
                traits: cell.accessibilityTraits
            )
        }

        let cell = try #require(read.first)
        #expect(!cell.identifiers.contains("reps-rail"), "\(cell.identifiers)")
        #expect(cell.label == "Reps 5")
        #expect(cell.traits.contains(.button))
        #expect(cell.traits.contains(.selected))
    }
}
