import SwiftUI
import Testing
import UIKit

@testable import WorkoutTracker

/// The branch in every frame the reading column can give it, from its floor past its full 156pt
/// drawing (#599). The coach note ends 18pt above the frame (the 4pt padding and the column's 14pt
/// gap) and Last Performed or the card starts 14pt below it, so the ink stays inside those gaps and a
/// leaf's tap box within 4pt above the frame and never below it. Every blade is drawn full length:
/// all Sets but the active one are logged, on the partner too.
@MainActor
@Suite
struct SessionStageBranchEnvelopeTests {
    @Test(arguments: [70, 90, 120, 156, 167] as [CGFloat], [3, 5, 8])
    func theExerciseBranchStaysInsideTheGapsAroundIt(height: CGFloat, setCount: Int) throws {
        let branch = Branch(setCount: setCount, partnerSetCount: nil)
        let ink = try #require(try branch.inkExtent(height: height), "the branch draws at \(height)pt")
        #expect(ink.top >= -(Theme.stageColumnSpacing + 4))
        #expect(ink.bottom <= height + Theme.stageColumnSpacing)

        let taps = try branch.tapBoxes(height: height)
        #expect(taps.count == setCount, "every Set has a leaf to tap")
        #expect(taps.map(\.minY).min() ?? 0 >= -4)
        #expect(taps.map(\.maxY).max() ?? 0 <= height)
    }

    @Test(arguments: [70, 90, 120, 156, 167] as [CGFloat], [3, 5, 8])
    func theSupersetBranchKeepsItsLateralInsideTheGapsAroundIt(height: CGFloat, setCount: Int) throws {
        let branch = Branch(setCount: setCount, partnerSetCount: 3)
        let ink = try #require(try branch.inkExtent(height: height), "the forked branch draws at \(height)pt")
        #expect(ink.top >= -(Theme.stageColumnSpacing + 4))
        #expect(ink.bottom <= height + Theme.stageColumnSpacing)
    }

    @Test func theBranchFillsItsRegionAndNeverFallsBelowItsFloor() {
        let branch = Branch(setCount: 3, partnerSetCount: nil)
        let heights = ([20, nil, 300] as [CGFloat?]).map { branch.height(proposing: $0) }
        #expect(heights == [70, 70, 300])
    }
}

@MainActor
private struct Branch {
    let setCount: Int
    let partnerSetCount: Int?

    var view: SessionStageBranch {
        let sets = Self.sets(count: setCount, order: 0, allLogged: false)
        return SessionStageBranch(
            sets: sets,
            activeSetID: ActiveSetID(exerciseOrder: 0, setIndex: setCount - 1),
            partnerSets: partnerSetCount.map { Self.sets(count: $0, order: 1, allLogged: true) },
            onTap: partnerSetCount == nil ? { _ in } : nil
        )
    }

    /// The height the branch takes when the column proposes `proposal` (`nil` asks for its ideal).
    func height(proposing proposal: CGFloat?) -> CGFloat {
        let renderer = ImageRenderer(content: view.environment(\.themePalette, Theme.palette(for: .day)))
        renderer.proposedSize = ProposedViewSize(width: 370, height: proposal)
        var height: CGFloat = 0
        renderer.render { size, _ in height = size.height }
        return height
    }

    /// The inked rows of an offscreen render, in points from the top of a `height` frame. It draws
    /// through Core Graphics because `cgImage` renders on the GPU, which comes back blank while a
    /// cold machine compiles its first stroke pipeline (#599).
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
        let context = try #require(
            CGContext(
                data: &pixels,
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
        let inkedRows = (0..<rows).filter { row in
            (0..<width).contains { column in pixels[(row * width + column) * 4 + 3] > 25 }
        }
        guard let top = inkedRows.first, let bottom = inkedRows.last else { return nil }
        return (CGFloat(top) / scale - margin, CGFloat(bottom + 1) / scale - margin)
    }

    /// The leaves' tap boxes, in points from the top of a `height` frame.
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
        return try AccessibilityHost.read(page, in: CGSize(width: 402, height: 874)) { window in
            window.accessibilityFrames { $0.accessibilityLabel?.hasPrefix("Set ") == true }
                .map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }
        }
    }

    private static func sets(count: Int, order: Int, allLogged: Bool) -> [ExerciseSet] {
        let exercise = Exercise(name: "Back Squat", baseName: "Back Squat", cadence: nil, coachNote: nil, order: order)
        exercise.sets = (0..<count).map { index in
            let isLogged = allLogged || index < count - 1
            let set = ExerciseSet(
                index: index,
                prescribedReps: "5",
                prescribedLoad: "RPE7",
                percentOneRM: nil,
                state: isLogged ? .logged : .pending
            )
            if isLogged { set.setLog = SetLog(weight: .pounds(235), reps: 5, rpe: .seven) }
            return set
        }
        return exercise.sets.sorted { $0.index < $1.index }
    }
}
