import SwiftUI
import Testing
import UIKit

@testable import WorkoutTracker

/// The branch at every height the reading column can give it, from its floor to its full 156pt
/// (#599). The coach note ends 18pt above the branch frame and Last Performed or the card starts
/// 14pt below it, so the ink stays within 14pt above and 10pt below the frame, and a leaf's tap box
/// within 4pt above and never below. Every blade is drawn full length: all Sets but the active one
/// are logged, on the partner too.
@MainActor
@Suite
struct SessionStageBranchEnvelopeTests {
    @Test(arguments: [70, 90, 120] as [CGFloat], [3, 5, 8])
    func theExerciseBranchStaysInsideTheGapsAroundIt(height: CGFloat, setCount: Int) throws {
        let branch = Branch(setCount: setCount, partnerSetCount: nil)
        let ink = try #require(try branch.inkExtent(height: height), "the branch draws at \(height)pt")
        #expect(ink.top >= -14)
        #expect(ink.bottom <= height + 10)

        let taps = try branch.tapBoxes(height: height)
        #expect(taps.count == setCount, "every Set has a leaf to tap")
        #expect(taps.map(\.minY).min() ?? 0 >= -4)
        #expect(taps.map(\.maxY).max() ?? 0 <= height)
    }

    @Test(arguments: [70, 90, 120] as [CGFloat], [3, 5, 8])
    func theSupersetBranchKeepsItsLateralInsideTheGapsAroundIt(height: CGFloat, setCount: Int) throws {
        let branch = Branch(setCount: setCount, partnerSetCount: 3)
        let ink = try #require(try branch.inkExtent(height: height), "the forked branch draws at \(height)pt")
        #expect(ink.top >= -14)
        #expect(ink.bottom <= height + 10)
    }

    @Test func theBranchNeverDrawsShorterThanItsFloorNorTallerThan156() {
        let branch = Branch(setCount: 3, partnerSetCount: nil).view
        let controller = UIHostingController(rootView: branch.environment(\.themePalette, Theme.palette(for: .day)))
        #expect(controller.sizeThatFits(in: CGSize(width: 370, height: 20)).height == 70)
        #expect(controller.sizeThatFits(in: CGSize(width: 370, height: 100)).height == 100)
        #expect(controller.sizeThatFits(in: CGSize(width: 370, height: 400)).height == 156)
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

    /// The inked rows of an offscreen render, in points from the top of a `height` frame.
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
        renderer.scale = scale
        let image = try #require(renderer.cgImage)
        let width = image.width
        var pixels = [UInt8](repeating: 0, count: width * image.height * 4)
        let context = try #require(
            CGContext(
                data: &pixels,
                width: width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: image.height))
        let inkedRows = (0..<image.height).filter { row in
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
