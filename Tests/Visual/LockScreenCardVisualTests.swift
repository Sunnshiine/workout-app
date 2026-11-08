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
    private static let lastPerformed = ["Block 26 · W4 D3 — 245×5 @6, 255×5 @7", "245×5 @6, 255×5 @7", "245×5 @6, …"]

    @Test func aCompletePreFillOffersRPEChipsDay() {
        assertCardBaseline(state(.light, press: Self.backSquatPress, lastPerformed: Self.lastPerformed))
    }

    @Test func aCompletePreFillOffersRPEChipsNight() {
        assertCardBaseline(state(.dark, press: Self.backSquatPress, lastPerformed: Self.lastPerformed))
    }

    @Test func noLastPerformedHoldsTheCardsHeightDay() {
        assertCardBaseline(state(.light, press: Self.backSquatPress, lastPerformed: []))
    }

    @Test func noLastPerformedHoldsTheCardsHeightNight() {
        assertCardBaseline(state(.dark, press: Self.backSquatPress, lastPerformed: []))
    }

    @Test func noCompletePreFillLeavesTheMicAndTheAppDay() {
        assertCardBaseline(state(.light, press: .needsApp, lastPerformed: []))
    }

    @Test func noCompletePreFillLeavesTheMicAndTheAppNight() {
        assertCardBaseline(state(.dark, press: .needsApp, lastPerformed: Self.lastPerformed))
    }

    @Test func theLongestCellsStayOnTheCardDay() {
        assertCardBaseline(Self.longestCells(.light, press: Self.heaviestPress))
    }

    @Test func theLongestCellsStayOnTheCardNight() {
        assertCardBaseline(Self.longestCells(.dark, press: Self.heaviestPress))
    }

    @Test func theLongestCellsWithNoChipsStayOnTheCardNight() {
        assertCardBaseline(Self.longestCells(.dark, press: .needsApp))
    }

    @Test func aBodyweightPreFillWithNoPrescribedRPENight() {
        assertCardBaseline(
            Self.makeState(
                Prescription(exerciseName: "Pull-Up", reps: "12", load: "BW"),
                .dark,
                press: Self.bodyweightPress,
                lastPerformed: ["Block 26 · W4 D3 — BW×12 @7", "BW×12 @7"]
            )
        )
    }

    @Test func aQueueTheSheetDoesNotHaveYetStandsBesideTheValuesDay() {
        assertCardBaseline(state(.light, press: Self.backSquatPress, lastPerformed: Self.lastPerformed, pendingWrites: 3))
    }

    @Test func aQueueTheSheetDoesNotHaveYetStandsBesideTheValuesNight() {
        assertCardBaseline(state(.dark, press: Self.backSquatPress, lastPerformed: Self.lastPerformed, pendingWrites: 3))
    }

    @Test func theLargestTypeKeepsEveryLineAndChipOnTheCard() {
        assertCardBaseline(state(.dark, press: Self.backSquatPress, lastPerformed: Self.lastPerformed), dynamicTypeSize: .xxxLarge)
    }

    @Test func aLongLastPerformedGivesUpTheAddressBeforeASetLog() {
        assertCardBaseline(
            state(
                .dark,
                press: Self.backSquatPress,
                lastPerformed: [
                    "Block 26 · W4 D3 — 1005×10 @8.5, 1015×10 @9, 1025×10 @9.5, 1035×10 @10",
                    "1005×10 @8.5, 1015×10 @9, 1025×10 @9.5, 1035×10 @10",
                    "1005×10 @8.5, 1015×10 @9, 1025×10 @9.5, …",
                    "1005×10 @8.5, 1015×10 @9, …",
                    "1005×10 @8.5, …"
                ]
            )
        )
    }

    @Test func theLargestTypeKeepsLastPerformedWithNoChips() {
        assertCardBaseline(state(.dark, press: .needsApp, lastPerformed: Self.lastPerformed), dynamicTypeSize: .xxxLarge)
    }

    @Test func theQueueTakesTheSpareLineWhereItFitsBesideNothing() {
        assertCardBaseline(Self.dropSet(.dark), dynamicTypeSize: .xxxLarge)
    }

    @Test func aCardShortOfRoomGivesUpLastPerformedBeforeAChip() {
        assertCardBaseline(
            state(.dark, press: Self.backSquatPress, lastPerformed: Self.lastPerformed),
            dynamicTypeSize: .xxxLarge,
            height: Self.systemHeight(at: .large)
        )
    }

    @Test func theNarrowestPhoneKeepsEveryChipOnTheCard() {
        assertCardBaseline(state(.dark, press: Self.backSquatPress, lastPerformed: Self.lastPerformed, pendingWrites: 3), width: 347)
    }

    @Test func theSessionsLastSetReadsBackOverItsSets() {
        assertCardBaseline(
            Self.makeState(
                Prescription(exerciseName: "Back Squat", reps: "5", load: "RPE7"),
                .dark,
                press: .needsApp,
                lastPerformed: [],
                dictation: .logged(
                    "252.5×5 @7",
                    to: LiveActivityWrittenSet(exerciseName: "Back Squat", setOrdinal: 3, setsTotal: 3)
                ),
                setsDone: 3,
                restEnd: nil
            )
        )
    }

    @Test func aReadbackNamesALongNextExerciseBesideItsBar() {
        assertCardBaseline(
            Self.makeState(
                Prescription(exerciseName: "Paused Low-Bar Competition Back Squat w/ Safety Squat Bar", reps: "5", load: "RPE7"),
                .dark,
                press: .needsApp,
                lastPerformed: [],
                dictation: Self.logged
            )
        )
    }

    @Test func aLongReasonStaysOnItsLineAtTheLargestType() {
        assertCardBaseline(
            state(.dark, dictation: Self.longReason),
            dynamicTypeSize: .xxxLarge
        )
    }

    @Test func aPressReadsBackInTheCardsShapeDay() {
        assertCardBaseline(state(.light, dictation: Self.logged))
    }

    @Test func aPressReadsBackInTheCardsShapeNight() {
        assertCardBaseline(state(.dark, dictation: Self.logged))
    }

    @Test func aPressReadsBackAtTheLargestType() {
        assertCardBaseline(state(.dark, dictation: Self.logged), dynamicTypeSize: .xxxLarge)
    }

    @Test func aRefusalNamesTheSetItFoundDay() {
        assertCardBaseline(state(.light, dictation: Self.refused))
    }

    @Test func aRefusalNamesTheSetItFoundNight() {
        assertCardBaseline(state(.dark, dictation: Self.refused))
    }

    @Test func aRefusalReadsBackAtTheLargestType() {
        assertCardBaseline(state(.dark, dictation: Self.refused), dynamicTypeSize: .xxxLarge)
    }

    @Test func listeningKeepsTheCardsShapeNight() {
        assertCardBaseline(state(.dark, dictation: .listening))
    }

    private static let backSquatPress = LoggablePress.ready(
        LoggablePress.Offer(
            weight: "252.5",
            reps: 5,
            rpeChoices: ["6", "6.5", "7", "7.5", "8"],
            prescribedRPE: "7",
            setIdentity: "visual"
        )
    )

    private static let heaviestPress = LoggablePress.ready(
        LoggablePress.Offer(
            weight: "1025.5",
            reps: 10,
            rpeChoices: ["8", "8.5", "9", "9.5", "10"],
            prescribedRPE: nil,
            setIdentity: "visual"
        )
    )

    private static let bodyweightPress = LoggablePress.ready(
        LoggablePress.Offer(
            weight: "BW",
            reps: 12,
            rpeChoices: ["6", "6.5", "7", "7.5", "8"],
            prescribedRPE: nil,
            setIdentity: "visual"
        )
    )

    private static let backSquatSet = LiveActivityWrittenSet(exerciseName: "Back Squat", setOrdinal: 2, setsTotal: 3)
    private static let logged = LiveActivityDictation.logged("252.5×5 @7", to: backSquatSet)
    private static let refused = LiveActivityDictation.settled(setLog: "252.5×5 @8", backSquatSet)
    private static let longReason = LiveActivityDictation.notLogged("Couldn’t read that tap. Open to log")

    private struct Prescription {
        let exerciseName: String
        let reps: String
        let load: String
    }

    private static func longestCells(_ appearance: LiveActivityAppearance, press: LoggablePress) -> WorkoutActivityAttributes.ContentState {
        makeState(
            Prescription(
                exerciseName: "Paused Low-Bar Competition Back Squat w/ Safety Squat Bar",
                reps: "AMRAP",
                load: "Start conservative and work up to a heavy single"
            ),
            appearance,
            press: press,
            lastPerformed: [
                "Block 26 · W4 D3 — 1025.5×1 @10, 1015×1 @9.5, felt heavy belt off knee wraps on",
                "1025.5×1 @10, 1015×1 @9.5, felt heavy belt off knee wraps on",
                "1025.5×1 @10, 1015×1 @9.5, …",
                "1025.5×1 @10, …"
            ]
        )
    }

    /// A drop Set with writes still queued, which the chips cannot log and nothing was performed of.
    private static func dropSet(_ appearance: LiveActivityAppearance) -> WorkoutActivityAttributes.ContentState {
        makeState(
            Prescription(exerciseName: "BB RDL", reps: "8", load: "Drop 17.5%"),
            appearance,
            press: .needsApp,
            lastPerformed: [],
            pendingWrites: 4
        )
    }

    private func state(
        _ appearance: LiveActivityAppearance,
        press: LoggablePress = .needsApp,
        lastPerformed: [String] = [],
        pendingWrites: Int = 0,
        dictation: LiveActivityDictation? = nil
    ) -> WorkoutActivityAttributes.ContentState {
        Self.makeState(
            Prescription(exerciseName: "Back Squat", reps: "5", load: "RPE7"),
            appearance,
            press: press,
            lastPerformed: lastPerformed,
            pendingWrites: pendingWrites,
            dictation: dictation,
            setsDone: dictation == nil ? 1 : 2
        )
    }

    private static func makeState(
        _ prescription: Prescription,
        _ appearance: LiveActivityAppearance,
        press: LoggablePress,
        lastPerformed: [String],
        pendingWrites: Int = 0,
        dictation: LiveActivityDictation? = nil,
        setsDone: Int = 1,
        restEnd: Date? = Date(timeIntervalSinceReferenceDate: 1_000)
    ) -> WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            exerciseName: prescription.exerciseName,
            prescribedReps: prescription.reps,
            prescribedLoad: prescription.load,
            weightValue: "",
            weightUnit: "",
            setsDone: setsDone,
            setsTotal: 3,
            variant: .restTimerSetsLeft,
            appearance: appearance,
            restStartDate: restEnd?.addingTimeInterval(-120),
            restEndDate: restEnd,
            dictation: dictation,
            loggablePress: press,
            lastPerformed: lastPerformed,
            pendingWrites: pendingWrites
        )
    }

    private func assertCardBaseline(
        _ state: WorkoutActivityAttributes.ContentState,
        dynamicTypeSize: DynamicTypeSize = WorkoutVisualBaseline.dynamicTypeSize,
        width: CGFloat = cardWidth,
        height: CGFloat? = nil,
        testName: String = #function
    ) {
        let height = height ?? Self.systemHeight(at: dynamicTypeSize)
        let view = Self.card(state)
            .frame(width: width, height: height, alignment: .top)
            .background(state.liveActivityColors.background)
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

    @ViewBuilder
    fileprivate static func card(_ state: WorkoutActivityAttributes.ContentState) -> some View {
        if let dictation = state.dictation {
            if dictation.isAboutASet {
                DictationLockScreenView(state: state, dictation: dictation)
            } else {
                NoSetLockScreenView(state: state, dictation: dictation)
            }
        } else {
            SetOfferLockScreenView(state: state)
        }
    }
}

/// At every type size up to where DESIGN.md's Product Scale Rule stops it, each state keeps every
/// line in the height the system gives it. The system can keep a card's last height until the screen
/// wakes, so a readback is never shorter than the card of the Set it moves on to.
extension LockScreenCardVisualTests {
    @Test func everyStateKeepsEveryLineAtEveryTypeSize() throws {
        for size in DynamicTypeSize.allCases where size <= .xxxLarge {
            let offers = [
                state(.dark, press: Self.backSquatPress, lastPerformed: Self.lastPerformed),
                state(.dark, press: Self.backSquatPress),
                state(.dark, press: .needsApp, lastPerformed: Self.lastPerformed),
                Self.longestCells(.dark, press: Self.heaviestPress),
                Self.longestCells(.dark, press: .needsApp),
                Self.dropSet(.dark)
            ]
            .map { height(of: $0, at: size) }
            let readbacks = [Self.logged, Self.refused, .listening, Self.longReason]
                .map { height(of: state(.dark, dictation: $0), at: size) }
            let noSet = [LiveActivityDictation.noSetLeft(session: "Block 27 · W1 D1"), .noCurrentSession]
                .map { height(of: state(.dark, dictation: $0), at: size) }
            for height in offers + readbacks + noSet {
                #expect(height <= Self.systemHeight(at: size), "At \(size) a card drew \(height)pt")
            }
            let shortestReadback = try #require(readbacks.min())
            let tallestOffer = try #require(offers.max())
            #expect(shortestReadback >= tallestOffer, "At \(size) a readback drew \(readbacks) over cards of \(offers)")
        }
    }

    private func height(of state: WorkoutActivityAttributes.ContentState, at size: DynamicTypeSize) -> CGFloat {
        let card = Self.card(state)
            .environment(\.dynamicTypeSize, size)
            .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
        let unbounded = CGSize(width: Self.cardWidth, height: .greatestFiniteMagnitude)
        return UIHostingController(rootView: card).sizeThatFits(in: unbounded).height
    }
}
