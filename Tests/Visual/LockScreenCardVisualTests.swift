import SnapshotTesting
import SwiftUI
import Testing

@testable import WorkoutTracker

/// The Lock Screen card in each palette the Live Activity Lab can choose, on a rest long over so the
/// countdown reads a stable `Ready`. The production activity always takes the dark palette. Each draws
/// at the width a card lays out at, in the height the system gives it at its type size, so a state
/// that outgrew the card would show cut off.
@MainActor
@Suite(.snapshots(record: .never))
struct LockScreenCardVisualTests {
    private static let cardWidth: CGFloat = 374
    private static let narrowestPhone: CGFloat = 347

    @Test func theCardAtRestDay() {
        assertCardBaseline(LockScreenCardSet.backSquat.state(.light))
    }

    @Test func theCardAtRestNight() {
        assertCardBaseline(LockScreenCardSet.backSquat.state(.dark))
    }

    @Test func theCoachNoteOpensWhereTheNumbersWereDay() {
        assertCardBaseline(LockScreenCardSet.backSquat.state(.light, face: .coachNote))
    }

    @Test func theCoachNoteOpensWhereTheNumbersWereNight() {
        assertCardBaseline(LockScreenCardSet.backSquat.state(.dark, face: .coachNote))
    }

    @Test func logOffersTheRepsDay() {
        assertCardBaseline(LockScreenCardSet.backSquat.state(.light, face: .reps))
    }

    @Test func logOffersTheRepsNight() {
        assertCardBaseline(LockScreenCardSet.backSquat.state(.dark, face: .reps))
    }

    @Test func aRepsTapOffersTheRPEDay() {
        assertCardBaseline(LockScreenCardSet.backSquat.state(.light, face: .rpe(reps: 6)))
    }

    @Test func aRepsTapOffersTheRPENight() {
        assertCardBaseline(LockScreenCardSet.backSquat.state(.dark, face: .rpe(reps: 6)))
    }

    @Test func noCoachNoteLeavesNoNoteButtonNight() {
        assertCardBaseline(LockScreenCardSet.noCoachNote.state(.dark))
    }

    @Test func noCadenceMovesTheNumbersUpDay() {
        assertCardBaseline(LockScreenCardSet.noCadence.state(.light))
    }

    @Test func noCadenceMovesTheNumbersUpNight() {
        assertCardBaseline(LockScreenCardSet.noCadence.state(.dark))
    }

    @Test func theWorstCaseStaysReadableDay() {
        assertCardBaseline(LockScreenCardSet.worstCase.state(.light))
    }

    @Test func theWorstCaseStaysReadableNight() {
        assertCardBaseline(LockScreenCardSet.worstCase.state(.dark))
    }

    @Test func aLongCoachNoteKeepsToTwoLinesNight() {
        assertCardBaseline(LockScreenCardSet.worstCase.state(.dark, face: .coachNote))
    }

    @Test func aSetTheCardCannotLogOpensTheAppDay() {
        assertCardBaseline(LockScreenCardSet.noWeight.state(.light))
    }

    @Test func aSetTheCardCannotLogOpensTheAppNight() {
        assertCardBaseline(LockScreenCardSet.noWeight.state(.dark))
    }

    @Test func anExerciseThatOpensOnAHoldOffersItsStartDay() {
        assertCardBaseline(LockScreenCardSet.openingHold.state(.light))
    }

    @Test func anExerciseThatOpensOnAHoldOffersItsStartNight() {
        assertCardBaseline(LockScreenCardSet.openingHold.state(.dark))
    }

    @Test func aBodyweightSetWithNoPrescribedRPENight() {
        assertCardBaseline(LockScreenCardSet.bodyweight.state(.dark))
    }

    @Test func theLargestTypeKeepsTheCardAtRest() {
        assertCardBaseline(LockScreenCardSet.backSquat.state(.dark), dynamicTypeSize: .xxxLarge)
    }

    @Test func theLargestTypeKeepsTheCardAtRestDay() {
        assertCardBaseline(LockScreenCardSet.backSquat.state(.light), dynamicTypeSize: .xxxLarge)
    }

    @Test func theLargestTypeKeepsTheWorstCase() {
        assertCardBaseline(LockScreenCardSet.worstCase.state(.dark), dynamicTypeSize: .xxxLarge)
    }

    @Test func theLargestTypeKeepsTheCoachNote() {
        assertCardBaseline(LockScreenCardSet.worstCase.state(.dark, face: .coachNote), dynamicTypeSize: .xxxLarge)
    }

    @Test func theLargestTypeKeepsEveryRepsChoice() {
        assertCardBaseline(LockScreenCardSet.backSquat.state(.dark, face: .reps), dynamicTypeSize: .xxxLarge)
    }

    @Test func theLargestTypeKeepsEveryRPEChoice() {
        assertCardBaseline(LockScreenCardSet.worstCase.state(.dark, face: .rpe(reps: 12)), dynamicTypeSize: .xxxLarge)
    }

    @Test func theNarrowestPhoneKeepsTheWorstCase() {
        assertCardBaseline(LockScreenCardSet.worstCase.state(.dark), width: Self.narrowestPhone)
    }

    @Test func theNarrowestPhoneKeepsEveryRPEChoiceAndTheWayBack() {
        assertCardBaseline(LockScreenCardSet.worstCase.state(.dark, face: .rpe(reps: 12)), width: Self.narrowestPhone)
    }

    @Test func theSessionsLastSetReadsBackOverItsSets() {
        assertCardBaseline(
            LockScreenCardSet(press: .needsApp, setsDone: 3, restEnd: nil)
                .state(
                    .dark,
                    dictation: .logged(
                        "252.5×5 @7",
                        to: LiveActivityWrittenSet(exerciseName: "Back Squat", setOrdinal: 3, setsTotal: 3)
                    )
                )
        )
    }

    @Test func aReadbackNamesALongNextExerciseBesideItsBar() {
        assertCardBaseline(
            LockScreenCardSet(
                exerciseName: "Paused Low-Bar Competition Back Squat w/ Safety Squat Bar",
                press: .needsApp,
                pendingWrites: 1
            )
            .state(.dark, dictation: Self.logged)
        )
    }

    @Test func aLongReasonStaysOnItsLineAtTheLargestType() {
        assertCardBaseline(readback(.dark, Self.longReason), dynamicTypeSize: .xxxLarge)
    }

    @Test func aPressReadsBackInTheCardsShapeDay() {
        assertCardBaseline(readback(.light, Self.logged))
    }

    @Test func aPressReadsBackInTheCardsShapeNight() {
        assertCardBaseline(readback(.dark, Self.logged))
    }

    @Test func aPressReadsBackAtTheLargestType() {
        assertCardBaseline(readback(.dark, Self.logged), dynamicTypeSize: .xxxLarge)
    }

    @Test func aRefusalNamesTheSetItFoundDay() {
        assertCardBaseline(readback(.light, Self.refused))
    }

    @Test func aRefusalNamesTheSetItFoundNight() {
        assertCardBaseline(readback(.dark, Self.refused))
    }

    @Test func aRefusalReadsBackAtTheLargestType() {
        assertCardBaseline(readback(.dark, Self.refused), dynamicTypeSize: .xxxLarge)
    }

    @Test func listeningKeepsTheCardsShapeNight() {
        assertCardBaseline(readback(.dark, .listening))
    }

    private static let backSquatSet = LiveActivityWrittenSet(exerciseName: "Back Squat", setOrdinal: 2, setsTotal: 3)
    private static let logged = LiveActivityDictation.logged("252.5×5 @7", to: backSquatSet)
    private static let refused = LiveActivityDictation.settled(setLog: "252.5×5 @8", backSquatSet)
    private static let longReason = LiveActivityDictation.notLogged("Couldn’t read that tap. Open to log")

    private func readback(
        _ appearance: LiveActivityAppearance,
        _ dictation: LiveActivityDictation
    ) -> WorkoutActivityAttributes.ContentState {
        LockScreenCardSet(cadence: nil, coachNote: nil, press: .needsApp, setsDone: 2).state(appearance, dictation: dictation)
    }

    private func assertCardBaseline(
        _ state: WorkoutActivityAttributes.ContentState,
        dynamicTypeSize: DynamicTypeSize = WorkoutVisualBaseline.dynamicTypeSize,
        width: CGFloat = cardWidth,
        testName: String = #function
    ) {
        let height = Self.systemHeight(at: dynamicTypeSize)
        let view = LockScreenCard(state: state)
            .frame(width: width, height: height, alignment: .top)
            .background { LockScreenCardBackground(leaf: state.lockScreenLeaf, restFill: state.wholeRestInterval) }
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))

        assertSnapshot(
            of: view,
            as: .image(
                precision: WorkoutVisualBaseline.labelAntialiasingPrecision,
                layout: .fixed(width: width, height: height),
                traits: UITraitCollection { traits in
                    traits.displayScale = 3
                    traits.userInterfaceStyle = state.appearance == .dark ? .dark : .light
                }
            ),
            testName: testName
        )
    }
}

extension LockScreenCardVisualTests {
    /// The height the system offers a Lock Screen card, measured on the iOS 27 simulator with a card
    /// of fixed-height rungs in a `ViewThatFits`: 160pt up to `.large`, then at least 170, 185, and
    /// 200. A card shows the rung that fits.
    fileprivate static func systemHeight(at size: DynamicTypeSize) -> CGFloat {
        switch size {
        case ...DynamicTypeSize.large: 160
        case .xLarge: 170
        case .xxLarge: 185
        default: 200
        }
    }

    private static var everyFace: [WorkoutActivityAttributes.ContentState] {
        [
            LockScreenCardSet.backSquat.state(.dark),
            LockScreenCardSet.backSquat.state(.dark, face: .coachNote),
            LockScreenCardSet.backSquat.state(.dark, face: .reps),
            LockScreenCardSet.backSquat.state(.dark, face: .rpe(reps: 6)),
            LockScreenCardSet.neitherCadenceNorCoachNote.state(.dark),
            LockScreenCardSet.worstCase.state(.dark),
            LockScreenCardSet.worstCase.state(.dark, face: .coachNote),
            LockScreenCardSet.worstCase.state(.dark, face: .rpe(reps: 12)),
            LockScreenCardSet.noWeight.state(.dark),
            LockScreenCardSet.openingHold.state(.dark),
            LockScreenCardSet.bodyweight.state(.dark)
        ]
    }

    /// The system can keep a card's last height until the screen wakes, so every state draws at the
    /// one height the system gives the type size, and none is left cut off by the one before it.
    @Test func everyStateFillsTheHeightTheSystemGives() {
        let readbacks = [Self.logged, Self.refused, .listening, Self.longReason, .noSetLeft, .noCurrentSession]
            .map { readback(.dark, $0) }
        for size in DynamicTypeSize.allCases where size <= .xxxLarge {
            for state in Self.everyFace + readbacks {
                let card = LockScreenCard(state: state).environment(\.dynamicTypeSize, size)
                #expect(height(of: card) == Self.systemHeight(at: size), "At \(size), \(state.face) of \(state.exerciseName)")
            }
        }
    }

    /// At every type size up to where DESIGN.md's Product Scale Rule stops it, each face keeps every
    /// line inside the card's padding, so nothing on it is cut off or drawn over.
    @Test func everyFaceKeepsEveryLineAtEveryTypeSize() {
        for size in DynamicTypeSize.allCases where size <= .xxxLarge {
            let room = Self.systemHeight(at: size) - 2 * LockScreenCardMetrics.padding
            for state in Self.everyFace {
                let face = Self.face(of: state)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.dynamicTypeSize, size)
                let width = Self.narrowestPhone - 2 * LockScreenCardMetrics.padding
                #expect(height(of: face, width: width) <= room, "At \(size), \(state.face) of \(state.exerciseName)")
            }
        }
    }

    @ViewBuilder
    private static func face(of state: WorkoutActivityAttributes.ContentState) -> some View {
        switch (state.face, state.loggablePress) {
        case (.reps, .ready(let offer)): LockScreenChoicesFace(state: state, offer: offer, chosenReps: nil)
        case (.rpe(let reps), .ready(let offer)): LockScreenChoicesFace(state: state, offer: offer, chosenReps: reps)
        default: LockScreenRestFace(state: state)
        }
    }

    private func height(of view: some View, width: CGFloat = cardWidth) -> CGFloat {
        let localized = view.environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
        let unbounded = CGSize(width: width, height: .greatestFiniteMagnitude)
        return UIHostingController(rootView: localized).sizeThatFits(in: unbounded).height
    }
}
