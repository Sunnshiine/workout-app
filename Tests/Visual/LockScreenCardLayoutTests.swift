import SwiftUI
import Testing
import UIKit

@testable import WorkoutTracker

/// What VoiceOver reads of the Lock Screen card and where each control draws, at every type size up
/// to where DESIGN.md's Product Scale Rule stops it, on the narrowest phone and the widest card.
@MainActor
@Suite
struct LockScreenCardLayoutTests {
    private static let widths: [CGFloat] = [347, 374]
    /// A card draws at 97% of the size it lays out at, so a control this size draws 44pt.
    private static let smallestControl: CGFloat = 44 / 0.97

    @Test(arguments: LockScreenCardReading.all)
    func theCardReadsWholeAndKeepsEveryControlATapWide(_ face: LockScreenCardReading) throws {
        for size in DynamicTypeSize.allCases where size <= .xxxLarge {
            for drawn in try Self.drawing(of: face, at: size) {
                #expect(drawn.reads == face.reads, "\(face) at \(size), \(drawn.width)pt")
                #expect(drawn.pastTheCard.isEmpty, "\(face) at \(size), \(drawn.width)pt")
                #expect(drawn.tooSmallToTap.isEmpty, "\(face) at \(size), \(drawn.width)pt")
                #expect(drawn.overlapping.isEmpty, "\(face) at \(size), \(drawn.width)pt")
            }
        }
    }

    /// The system's render of a Live Activity cuts a wrapped Text set at an exact line height with
    /// no "…", which no render in this process shows. The Coach Note is the card's one wrapped text.
    @Test func theCoachNoteTakesItsLeadingBetweenItsLines() {
        #expect(LiveActivityType.coachNote.leading == .wrapped(1.5))
    }

    @Test func aRoleSetInALineBoxStaysOnOneLine() {
        let cadence = Text(String(repeating: "2-3:1:0 ", count: 20))
            .liveActivityFont(.caption)
            .environment(\.dynamicTypeSize, .large)

        let height = UIHostingController(rootView: cadence).sizeThatFits(in: CGSize(width: 120, height: 400)).height

        #expect(abs(height - 1.3 * 12) < 0.5)
    }

    struct Drawing {
        var width: CGFloat
        /// Every element's label, in the order VoiceOver reads them.
        var reads: [String]
        /// Each element drawn past the card's edges, by its label.
        var pastTheCard: [String]
        /// Each control drawn smaller than a thumb finds, by its label.
        var tooSmallToTap: [String]
        /// Each pair of controls drawn over one another, by their labels.
        var overlapping: [String]
    }

    private static func drawing(of face: LockScreenCardReading, at size: DynamicTypeSize) throws -> [Drawing] {
        let state = face.set.state(.dark, face: face.face)
        let height = LockScreenCardMetrics.height(at: size)
        let view = VStack(spacing: 0) {
            LockScreenCard(state: state)
                .environment(\.dynamicTypeSize, size)
                .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
        return try AccessibilityHost.read(view, in: widths.map { CGSize(width: $0, height: 400) }) { window in
            let card = CGRect(x: 0, y: 0, width: window.frame.width, height: height).insetBy(dx: -0.5, dy: -0.5)
            let named = window.accessibilityTree.compactMap { element -> (label: String, frame: CGRect, isControl: Bool)? in
                guard let label = element.accessibilityLabel, element.drawnFrame != .zero else { return nil }
                let traits = element.accessibilityTraits
                return (label, element.drawnFrame, traits.contains(.button) || traits.contains(.link))
            }
            let controls = named.filter(\.isControl)
            let overlapping = controls.enumerated().flatMap { index, control in
                controls.dropFirst(index + 1)
                    .filter { $0.frame.insetBy(dx: 0.5, dy: 0.5).intersects(control.frame) }
                    .map { "\(control.label) over \($0.label)" }
            }
            return Drawing(
                width: window.frame.width,
                reads: named.map(\.label),
                pastTheCard: named.filter { !card.contains($0.frame) }.map(\.label),
                tooSmallToTap: controls.filter { min($0.frame.width, $0.frame.height) < smallestControl - 0.5 }.map(\.label),
                overlapping: overlapping
            )
        }
    }
}

/// One face of one Set, and what VoiceOver reads of it, in order.
struct LockScreenCardReading: CustomTestStringConvertible, Sendable {
    let name: String
    let set: LockScreenCardSet
    var face = LockScreenCardFace.rest
    let reads: [String]

    var testDescription: String { name }

    static let all = [
        LockScreenCardReading(
            name: "at rest",
            set: .backSquat,
            reads: ["Ready", "Say Set", "Show the Coach Note", "Cadence 3:1:1", "252.5 pounds", "5 Reps", "RPE 7", "Log this Set"]
        ),
        LockScreenCardReading(
            name: "the Coach Note open",
            set: .backSquat,
            face: .coachNote,
            reads: ["Ready", "Cadence 3:1:1", LockScreenCardSet.coachNote, "Close the Coach Note"]
        ),
        LockScreenCardReading(
            name: "the Reps",
            set: .backSquat,
            face: .reps,
            reads: ["Back", "Reps", "252.5 lbs", "3 reps", "4 reps", "5 reps", "6 reps", "7 reps"]
        ),
        LockScreenCardReading(
            name: "the RPE",
            set: .backSquat,
            face: .rpe(reps: 6),
            reads: ["Back to the Reps", "RPE", "252.5 lbs · 6 reps"]
                + ["6", "6.5", "7", "7.5", "8"].map { "Log 252.5 lbs for 6 at RPE \($0)" }
        ),
        LockScreenCardReading(
            name: "no Cadence and no Coach Note",
            set: .neitherCadenceNorCoachNote,
            reads: ["Ready", "Say Set", "252.5 pounds", "5 Reps", "RPE 7", "Log this Set"]
        ),
        LockScreenCardReading(
            name: "the worst case",
            set: .worstCase,
            reads: ["Ready", "Say Set", "Show the Coach Note", "Cadence 2-3:1:0", "1002.5 pounds", "AMRAP Reps", "No RPE", "Log this Set"]
        ),
        LockScreenCardReading(
            name: "the worst case's RPE",
            set: .worstCase,
            face: .rpe(reps: 12),
            reads: ["Back to the Reps", "RPE", "1,002.5 lbs · 12 reps"]
                + ["8", "8.5", "9", "9.5", "10"].map { "Log 1002.5 lbs for 12 at RPE \($0)" }
        ),
        LockScreenCardReading(
            name: "a Set the card cannot log",
            set: .noWeight,
            reads: [
                "Ready", "Say Set", "Show the Coach Note", "Cadence 3:1:1", "No weight", "8 Reps", "No RPE",
                "Open WorkoutTracker to log this Set"
            ]
        ),
        LockScreenCardReading(
            name: "a Set that opens on a hold",
            set: .openingHold,
            reads: [
                "Ready", "Start the 10 second hold", "Show the Coach Note", "Cadence 2-3:1:0", "185 pounds", "8 to 10 Reps",
                "No RPE", "Log this Set"
            ]
        )
    ]
}
