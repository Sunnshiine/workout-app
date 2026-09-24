import SwiftUI
import Testing
import UIKit

@testable import WorkoutTracker

@MainActor
@Suite
struct SessionStageBranchEnvelopeTests {
    nonisolated static let heights = Set(
        Array(stride(from: CGFloat(70), through: 200, by: 2)) + whereTheLateralsHangBinds
    ).sorted()
    nonisolated static let whereTheLateralsHangBinds = stride(from: CGFloat(156), through: 170, by: 0.5)
    static let setCounts = [3, 5, 8]
    static let inkAbove = Theme.stageColumnSpacing + Theme.stageBranchTopPadding
    static let inkBelow = Theme.stageColumnSpacing - 2

    @Test(arguments: heights)
    func theExerciseBranchStaysInsideTheGapsAroundIt(height: CGFloat) throws {
        for setCount in Self.setCounts {
            let branch = Branch(setCount: setCount, kind: .exercise)
            let ink = try #require(try branch.inkExtent(height: height), "the branch draws with \(setCount) Sets")
            #expect(ink.top >= -Self.inkAbove, "\(setCount) Sets")
            #expect(ink.bottom <= height + Self.inkBelow, "\(setCount) Sets")

            let taps = try branch.tapBoxes(height: height)
            #expect(taps.count == setCount, "every Set has a leaf to tap")
            #expect(taps.map(\.minY).min() ?? 0 >= -Theme.stageBranchTopPadding, "\(setCount) Sets")
            #expect(taps.map(\.maxY).max() ?? 0 <= height, "\(setCount) Sets")
        }
    }

    @Test(arguments: heights, PartnerEnding.allCases)
    func theSupersetBranchKeepsItsLateralInsideTheGapsAroundIt(height: CGFloat, partnerEnding: PartnerEnding) throws {
        let branch = Branch(setCount: 3, kind: .superset(partnerEnding: partnerEnding))
        let ink = try #require(try branch.inkExtent(height: height), "the forked branch draws")
        #expect(ink.top >= -Self.inkAbove)
        #expect(ink.bottom <= height + Self.inkBelow)
    }

    @Test func theBranchFillsItsRegionAndNeverFallsBelowItsFloor() {
        let branch = Branch(setCount: 3, kind: .exercise)
        let heights = ([20, nil, 300] as [CGFloat?]).map { branch.height(proposing: $0) }
        #expect(heights == [70, 70, 300])
    }
}

enum PartnerEnding: CaseIterable, Sendable {
    case logged
    case skipped
}

private enum BranchKind {
    case exercise
    case superset(partnerEnding: PartnerEnding)
}

@MainActor
private struct Branch {
    let setCount: Int
    let kind: BranchKind

    var view: SessionStageBranch {
        let partnerSets: [ExerciseSet]? =
            switch kind {
            case .exercise: nil
            case .superset(let ending): Self.sets(count: 3, order: 1, last: ending == .skipped ? .skipped : .logged)
            }
        return SessionStageBranch(
            sets: Self.sets(count: setCount, order: 0, last: .pending),
            activeSetID: ActiveSetID(exerciseOrder: 0, setIndex: setCount - 1),
            partnerSets: partnerSets,
            onTap: partnerSets == nil ? { _ in } : nil
        )
    }

    func height(proposing proposal: CGFloat?) -> CGFloat {
        let renderer = ImageRenderer(content: view.environment(\.themePalette, Theme.palette(for: .day)))
        renderer.proposedSize = ProposedViewSize(width: 370, height: proposal)
        var height: CGFloat = 0
        renderer.render { size, _ in height = size.height }
        return height
    }

    /// Draws through Core Graphics because `cgImage` renders on the GPU, which comes back blank while
    /// a cold machine compiles its first stroke pipeline.
    func inkExtent(height: CGFloat) throws -> (top: CGFloat, bottom: CGFloat)? {
        let margin: CGFloat = 80
        let scale: CGFloat = 3
        let renderer = ImageRenderer(
            content:
                view
                .frame(width: 370, height: height)
                .padding(.vertical, margin)
                .environment(\.themePalette, Theme.palette(for: .day))
        )
        let width = Int(370 * scale)
        let rows = Int((height + 2 * margin) * scale)
        var pixels = [UInt8](repeating: 0, count: width * rows * 4)
        return try pixels.withUnsafeMutableBytes { bytes in
            let context = try #require(
                CGContext(
                    data: bytes.baseAddress,
                    width: width,
                    height: rows,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            )
            context.scaleBy(x: scale, y: scale)
            renderer.render(rasterizationScale: scale) { _, draw in draw(context) }
            func isInked(_ row: Int) -> Bool {
                stride(from: row * width * 4 + 3, to: (row + 1) * width * 4, by: 4).contains { bytes[$0] > 25 }
            }
            guard let top = (0..<rows).first(where: isInked), let bottom = (0..<rows).last(where: isInked) else {
                return nil
            }
            return (CGFloat(top) / scale - margin, CGFloat(bottom + 1) / scale - margin)
        }
    }

    func tapBoxes(height: CGFloat) throws -> [CGRect] {
        let origin = CGPoint(x: 16, y: 200)
        let page =
            view
            .frame(width: 370, height: height)
            .padding(.leading, origin.x)
            .padding(.top, origin.y)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
            .environment(\.themePalette, Theme.palette(for: .day))
        return try AccessibilityHost.read(page, in: [CGSize(width: 402, height: 874)]) { window in
            window.accessibilityFrames { $0.accessibilityLabel?.hasPrefix("Set ") == true }
                .map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
        }[0]
    }

    private static func sets(count: Int, order: Int, last: SetState) -> [ExerciseSet] {
        let exercise = Exercise(name: "Back Squat", baseName: "Back Squat", cadence: nil, coachNote: nil, order: order)
        exercise.sets = (0..<count).map { index in
            let state = index < count - 1 ? SetState.logged : last
            let set = ExerciseSet(
                index: index,
                prescribedReps: "5",
                prescribedLoad: "RPE7",
                percentOneRM: nil,
                state: state
            )
            if state == .logged { set.setLog = SetLog(weight: .pounds(235), reps: 5, rpe: .seven) }
            return set
        }
        return exercise.sets.sorted { $0.index < $1.index }
    }
}
