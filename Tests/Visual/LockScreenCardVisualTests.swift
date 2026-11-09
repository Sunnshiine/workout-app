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
    private static let guidance = "3:1:1 · Brace hard off the floor, controlled descent."

    @Test func aSetOffersItsRepsDay() {
        assertCardBaseline(state(.light, press: Self.backSquatPress, guidance: Self.guidance))
    }

    @Test func aSetOffersItsRepsNight() {
        assertCardBaseline(state(.dark, press: Self.backSquatPress, guidance: Self.guidance))
    }

    @Test func aRepsTapOffersTheRPEDay() {
        assertCardBaseline(state(.light, press: Self.chose(6), guidance: Self.guidance))
    }

    @Test func aRepsTapOffersTheRPENight() {
        assertCardBaseline(state(.dark, press: Self.chose(6), guidance: Self.guidance))
    }

    @Test func noGuidanceHoldsTheCardsHeightNight() {
        assertCardBaseline(state(.dark, press: Self.backSquatPress))
    }

    @Test func noLoggablePressLeavesTheMicAndTheAppDay() {
        assertCardBaseline(state(.light, press: .needsApp, weight: nil))
    }

    @Test func noLoggablePressLeavesTheMicAndTheAppNight() {
        assertCardBaseline(state(.dark, press: .needsApp, weight: nil, guidance: Self.guidance))
    }

    @Test func anExerciseThatOpensOnAHoldOffersItsStartDay() {
        assertCardBaseline(Self.openingHold(.light))
    }

    @Test func anExerciseThatOpensOnAHoldOffersItsStartNight() {
        assertCardBaseline(Self.openingHold(.dark))
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

    @Test func aBodyweightSetWithNoPrescribedRPENight() {
        assertCardBaseline(
            Self.makeState(
                Prescription(exerciseName: "Pull-Up", reps: "12", load: "BW"),
                .dark,
                press: Self.bodyweightPress,
                weight: ("BW", "")
            )
        )
    }

    @Test func aQueueTheSheetDoesNotHaveYetLeadsTheGuidanceDay() {
        assertCardBaseline(state(.light, press: Self.backSquatPress, guidance: Self.guidance, pendingWrites: 3))
    }

    @Test func aQueueTheSheetDoesNotHaveYetLeadsTheGuidanceNight() {
        assertCardBaseline(state(.dark, press: Self.backSquatPress, guidance: Self.guidance, pendingWrites: 3))
    }

    @Test func theLargestTypeKeepsTheTargetAndEveryChip() {
        assertCardBaseline(state(.dark, press: Self.backSquatPress, guidance: Self.guidance), dynamicTypeSize: .xxxLarge)
    }

    @Test func theLargestTypeKeepsTheQueueAndEveryRPEChip() {
        assertCardBaseline(
            state(.dark, press: Self.chose(6), guidance: Self.guidance, pendingWrites: 3),
            dynamicTypeSize: .xxxLarge
        )
    }

    @Test func theLargestTypeKeepsTheTargetWithNoChips() {
        assertCardBaseline(state(.dark, press: .needsApp, weight: nil, guidance: Self.guidance), dynamicTypeSize: .xxxLarge)
    }

    @Test func theQueueStaysWhereNoChipIsOffered() {
        assertCardBaseline(Self.dropSet(.dark), dynamicTypeSize: .xxxLarge)
    }

    @Test func aCardShortOfRoomGivesUpTheGuidanceBeforeAChip() {
        assertCardBaseline(
            state(.dark, press: Self.backSquatPress, guidance: Self.guidance, pendingWrites: 3),
            dynamicTypeSize: .xxxLarge,
            height: Self.systemHeight(at: .large)
        )
    }

    @Test func theNarrowestPhoneKeepsEveryChipOnTheCard() {
        assertCardBaseline(state(.dark, press: Self.backSquatPress, guidance: Self.guidance, pendingWrites: 3), width: 347)
    }

    @Test func theNarrowestPhoneKeepsEveryRPEChipAndTheWayBack() {
        assertCardBaseline(state(.dark, press: Self.chose(12), guidance: Self.guidance), width: 347)
    }

    @Test func theSessionsLastSetReadsBackOverItsSets() {
        assertCardBaseline(
            Self.makeState(
                Prescription(exerciseName: "Back Squat", reps: "5", load: "RPE7"),
                .dark,
                press: .needsApp,
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
                pendingWrites: 1,
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

    private static let backSquatPress = LoggablePress.ready(offer(reps: [3, 4, 5, 6, 7], prescribed: [5], rpe: "7"))
    private static let heaviestPress = LoggablePress.ready(
        LoggablePress.Offer(
            repChoices: [1, 2, 3, 4, 5],
            prescribedReps: [],
            rpeChoices: ["8", "8.5", "9", "9.5", "10"],
            prescribedRPE: nil,
            setIdentity: "visual",
            chosenReps: nil
        )
    )
    private static let bodyweightPress = LoggablePress.ready(offer(reps: [10, 11, 12, 13, 14], prescribed: [12], rpe: nil))

    /// The row turned to RPE for the Reps tapped.
    private static func chose(_ reps: Int) -> LoggablePress {
        .ready(offer(reps: [3, 4, 5, 6, 7], prescribed: [5], rpe: "7", chosen: reps))
    }

    private static func offer(reps: [Int], prescribed: [Int], rpe: String?, chosen: Int? = nil) -> LoggablePress.Offer {
        LoggablePress.Offer(
            repChoices: reps,
            prescribedReps: prescribed,
            rpeChoices: ["6", "6.5", "7", "7.5", "8"],
            prescribedRPE: rpe,
            setIdentity: "visual",
            chosenReps: chosen
        )
    }

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
            weight: ("1025.5", "lbs"),
            guidance: "2-0-X-1 · Belt off, knee wraps on. Stop the Set the moment the bar speed drops off at all, "
                + "and note how far it slowed"
        )
    }

    /// A drop Set with writes still queued, which the chips cannot log and nothing was performed of.
    private static func dropSet(_ appearance: LiveActivityAppearance) -> WorkoutActivityAttributes.ContentState {
        makeState(
            Prescription(exerciseName: "BB RDL", reps: "8", load: "Drop 17.5%"),
            appearance,
            press: .needsApp,
            weight: nil,
            pendingWrites: 4
        )
    }

    /// The Exercise's Coach Note opens each Set on a hold, so the Start takes the mic's place.
    private static func openingHold(_ appearance: LiveActivityAppearance) -> WorkoutActivityAttributes.ContentState {
        let owner = CountdownRun.Owner(
            session: SessionCoordinate(blockTab: "Block 27", address: SessionAddress(week: 1, day: 1)),
            set: ActiveSetID(exerciseOrder: 2, setIndex: 0)
        )
        return makeState(
            Prescription(exerciseName: "BB RDL", reps: "8-10", load: "RPE 8-9"),
            appearance,
            press: .ready(offer(reps: [6, 7, 8, 9, 10], prescribed: [8, 9, 10], rpe: nil)),
            weight: ("185", "lbs"),
            guidance: "2-3:1:0 · Start w/ 10 sec hold, proceed to rep range.",
            start: LockScreenStartOffer(
                label: "10 s hold",
                spokenLabel: "10 second hold",
                url: AppEntryRequest.startTimedEffort(owner).url
            )
        )
    }

    private func state(
        _ appearance: LiveActivityAppearance,
        press: LoggablePress = .needsApp,
        weight: (value: String, unit: String)? = ("252.5", "lbs"),
        guidance: String? = nil,
        pendingWrites: Int = 0,
        dictation: LiveActivityDictation? = nil
    ) -> WorkoutActivityAttributes.ContentState {
        Self.makeState(
            Prescription(exerciseName: "Back Squat", reps: "5", load: "RPE7"),
            appearance,
            press: press,
            weight: weight,
            guidance: guidance,
            pendingWrites: pendingWrites,
            dictation: dictation,
            setsDone: dictation == nil ? 1 : 2
        )
    }

    private static func makeState(
        _ prescription: Prescription,
        _ appearance: LiveActivityAppearance,
        press: LoggablePress,
        weight: (value: String, unit: String)? = ("252.5", "lbs"),
        guidance: String? = nil,
        start: LockScreenStartOffer? = nil,
        pendingWrites: Int = 0,
        dictation: LiveActivityDictation? = nil,
        setsDone: Int = 1,
        restEnd: Date? = Date(timeIntervalSinceReferenceDate: 1_000)
    ) -> WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            exerciseName: prescription.exerciseName,
            prescribedReps: prescription.reps,
            prescribedLoad: prescription.load,
            weightValue: weight?.value ?? "",
            weightUnit: weight?.unit ?? "",
            setsDone: setsDone,
            setsTotal: 3,
            variant: .restTimerSetsLeft,
            appearance: appearance,
            restStartDate: restEnd?.addingTimeInterval(-120),
            restEndDate: restEnd,
            dictation: dictation,
            loggablePress: press,
            guidance: guidance,
            start: start,
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
                state(.dark, press: Self.backSquatPress, guidance: Self.guidance),
                state(.dark, press: Self.chose(6), guidance: Self.guidance, pendingWrites: 3),
                state(.dark, press: Self.backSquatPress),
                state(.dark, press: .needsApp, weight: nil, guidance: Self.guidance),
                Self.longestCells(.dark, press: Self.heaviestPress),
                Self.longestCells(.dark, press: .needsApp),
                Self.dropSet(.dark),
                Self.openingHold(.dark)
            ]
            .map { height(of: $0, at: size) }
            let readbacks = [Self.logged, Self.refused, .listening, Self.longReason]
                .map { height(of: state(.dark, dictation: $0), at: size) }
            let noSet = [LiveActivityDictation.noSetLeft, .noCurrentSession]
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
