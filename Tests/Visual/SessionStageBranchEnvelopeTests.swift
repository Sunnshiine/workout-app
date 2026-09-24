import SwiftUI
import Testing
import UIKit

@testable import WorkoutTracker

/// The branch in every frame the reading column can give it, every 2pt from its 70pt floor past its
/// full 156pt drawing, with 3, 5, and 8 Sets (#599). The coach note ends above the frame by the 4pt
/// padding and the column gap, and Last Performed or the card starts one column gap below it. So the
/// ink stays inside the gap above and 2pt clear of the next line below, and a leaf's tap box stays
/// within 4pt above the frame and never below it. Every blade is drawn full length: all Sets but
/// the active one are logged, and the partner's last Set is logged or skipped (its blade dashed).
@MainActor
@Suite
struct SessionStageBranchEnvelopeTests {
    nonisolated static let heights = stride(from: 70, through: 200, by: 2).map { CGFloat($0) }
    static let setCounts = [3, 5, 8]
    static let inkAbove = Theme.stageColumnSpacing + 4
    static let inkBelow = Theme.stageColumnSpacing - 2

    @Test(arguments: heights)
    func theExerciseBranchStaysInsideTheGapsAroundIt(height: CGFloat) throws {
        for setCount in Self.setCounts {
            let branch = Branch(setCount: setCount, partnerEnding: nil)
            let ink = try #require(try branch.inkExtent(height: height), "the branch draws with \(setCount) Sets")
            #expect(ink.top >= -Self.inkAbove, "\(setCount) Sets")
            #expect(ink.bottom <= height + Self.inkBelow, "\(setCount) Sets")

            let taps = try branch.tapBoxes(height: height)
            #expect(taps.count == setCount, "every Set has a leaf to tap")
            #expect(taps.map(\.minY).min() ?? 0 >= -4, "\(setCount) Sets")
            #expect(taps.map(\.maxY).max() ?? 0 <= height, "\(setCount) Sets")
        }
    }

    @Test(arguments: heights, PartnerEnding.allCases)
    func theSupersetBranchKeepsItsLateralInsideTheGapsAroundIt(height: CGFloat, partnerEnding: PartnerEnding) throws {
        for setCount in Self.setCounts {
            let branch = Branch(setCount: setCount, partnerEnding: partnerEnding)
            let ink = try #require(try branch.inkExtent(height: height), "the forked branch draws with \(setCount) Sets")
            #expect(ink.top >= -Self.inkAbove, "\(setCount) Sets")
            #expect(ink.bottom <= height + Self.inkBelow, "\(setCount) Sets")
        }
    }

    @Test func theBranchFillsItsRegionAndNeverFallsBelowItsFloor() {
        let branch = Branch(setCount: 3, partnerEnding: nil)
        let heights = ([20, nil, 300] as [CGFloat?]).map { branch.height(proposing: $0) }
        #expect(heights == [70, 70, 300])
    }
}

/// How a Superset partner's last Set ended: logged draws an inked blade, skipped a dashed one.
enum PartnerEnding: CaseIterable, Sendable {
    case logged
    case skipped
}

@MainActor
private struct Branch {
    let setCount: Int
    /// `nil` draws an Exercise branch; otherwise a Superset's, with a partner of 3 Sets.
    let partnerEnding: PartnerEnding?

    var view: SessionStageBranch {
        SessionStageBranch(
            sets: Self.sets(count: setCount, order: 0, last: .pending),
            activeSetID: ActiveSetID(exerciseOrder: 0, setIndex: setCount - 1),
            partnerSets: partnerEnding.map { Self.sets(count: 3, order: 1, last: $0 == .skipped ? .skipped : .logged) },
            onTap: partnerEnding == nil ? { _ in } : nil
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
        func isInked(_ row: Int) -> Bool {
            pixels.withUnsafeBufferPointer { buffer in
                stride(from: row * width * 4 + 3, to: (row + 1) * width * 4, by: 4).contains { buffer[$0] > 25 }
            }
        }
        guard let top = (0..<rows).first(where: isInked), let bottom = (0..<rows).last(where: isInked) else { return nil }
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

    /// Every Set but the last is logged, and the last ends `last`.
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
