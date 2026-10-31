import SwiftUI
import Testing
import UIKit

@testable import WorkoutTracker

/// Every control VoiceOver or a finger can reach on the Session stage and its Active Set Card
/// carries a label and a 44pt hit area that overlaps no other, at the default text size and the
/// largest, which the stage caps (DESIGN.md §8). A branch leaf only keeps its height: crowded
/// leaves narrow to their share. This host cannot read a ScrollView's content, so the scrolling
/// surfaces are audited in `AccessibilityAuditUITests`.
@MainActor
struct AccessibilityAuditTests {
    enum Surface: CaseIterable {
        case stage, worstCaseStage
    }

    @Test(arguments: Surface.allCases, [DynamicTypeSize.large, .accessibility5])
    func everyControlIsLabeledFingerSizedAndClearOfItsNeighbours(surface: Surface, size: DynamicTypeSize) throws {
        let controls = try AuditedControl.read(surface, at: size)

        #expect(!controls.isEmpty)
        for control in controls {
            #expect(!control.label.isEmpty, "an unlabeled control at \(control.frame)")
            #expect(control.frame.height >= 44, "\(control) is short of a finger")
            if !control.isBranchLeaf {
                #expect(control.frame.width >= 44, "\(control) is narrower than a finger")
            }
        }
        let reachable = controls.filter { !$0.visible.isNull && !$0.visible.isEmpty }
        for (index, control) in reachable.enumerated() {
            for other in reachable[(index + 1)...] {
                let overlap = control.visible.intersection(other.visible)
                #expect(overlap.width < 0.5 || overlap.height < 0.5, "\(control) overlaps \(other)")
            }
        }
    }
}

struct AuditedControl: CustomStringConvertible {
    let label: String
    let frame: CGRect
    let visible: CGRect

    var isBranchLeaf: Bool {
        label.hasPrefix("Set ") && label.contains(", ")
    }

    var description: String {
        "\"\(label)\" at \(frame.integral)"
    }

    @MainActor
    static func read(_ surface: AccessibilityAuditTests.Surface, at size: DynamicTypeSize) throws -> [AuditedControl] {
        switch surface {
        case .stage:
            try SessionPageHost.controls(at: size)
        case .worstCaseStage:
            try SessionPageHost.worstCaseControls(at: size)
        }
    }

    /// A control's visible frame is clipped to its ancestors, so a rail cell scrolled out of its
    /// strip is not read as overlapping the rail beside it.
    @MainActor
    static func controls(in window: UIWindow) -> [AuditedControl] {
        var controls: [AuditedControl] = []
        var visited: Set<ObjectIdentifier> = []
        func visit(_ object: NSObject, clip: CGRect) {
            guard visited.insert(ObjectIdentifier(object)).inserted else { return }
            let frame = object.drawnFrame
            let traits = object.accessibilityTraits
            let isControl = traits.contains(.button) || traits.contains(.adjustable)
            if object.isAccessibilityElement, isControl, !traits.contains(.notEnabled) {
                controls.append(
                    AuditedControl(label: object.accessibilityLabel ?? "", frame: frame, visible: frame.intersection(clip))
                )
            }
            let inner = frame.isEmpty ? clip : clip.intersection(frame)
            for child in children(of: object) {
                visit(child, clip: inner)
            }
        }
        visit(window, clip: window.bounds)
        return controls
    }

    @MainActor
    private static func children(of object: NSObject) -> [NSObject] {
        let listed = object.accessibilityElements?.compactMap { $0 as? NSObject }
        let indexed = (0..<max(object.accessibilityElementCount(), 0)).compactMap {
            object.accessibilityElement(at: $0) as? NSObject
        }
        return (listed ?? []) + indexed + ((object as? UIView)?.subviews ?? [])
    }
}
