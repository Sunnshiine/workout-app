import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import WorkoutTracker

/// Every Form Clip surface, on a drawn frame, so a render holds no movie and no running player. The
/// review and Compare render under both traits because their room is Night under either.
@MainActor
@Suite(.snapshots(record: .never))
struct FormClipVisualTests {
    @Test func cardOfferingAClipMatchesVisualBaseline() throws {
        try assertCard(holding: [], appearance: .day, colorScheme: .light, config: .workoutVisualBaseline)
    }

    @Test func cardOfferingAClipMatchesNightVisualBaseline() throws {
        try assertCard(holding: [], appearance: .night, colorScheme: .dark, config: .workoutVisualBaselineNight)
    }

    @Test func cardHoldingClipsMatchesVisualBaseline() throws {
        try assertCard(holding: [squat], appearance: .day, colorScheme: .light, config: .workoutVisualBaseline)
    }

    @Test func cardHoldingClipsMatchesNightVisualBaseline() throws {
        try assertCard(holding: [squat], appearance: .night, colorScheme: .dark, config: .workoutVisualBaselineNight)
    }

    @Test func reviewWithABarPathMatchesVisualBaseline() throws {
        try assertReview(of: squat, among: 2, at: 3.2, config: .workoutVisualBaseline)
    }

    @Test func reviewWithABarPathMatchesNightVisualBaseline() throws {
        try assertReview(of: squat, among: 2, at: 3.2, config: .workoutVisualBaselineNight)
    }

    @Test func reviewOfAClipWithNoPathMatchesVisualBaseline() throws {
        try assertReview(of: earlierSquat, among: 1, at: 0, config: .workoutVisualBaseline)
    }

    @Test func reviewWhereThePlateWasLostMatchesVisualBaseline() throws {
        try assertReview(of: lostPlate, among: 1, at: 6, config: .workoutVisualBaseline)
    }

    @Test func reviewOfTheLongestSetMatchesVisualBaseline() throws {
        try assertReview(of: longest, among: 12, at: 8.2, config: .workoutVisualBaseline)
    }

    @Test func compareMatchesVisualBaseline() throws {
        try assertCompare(squat, beside: earlierSquat, choices: [earlierSquat], config: .workoutVisualBaseline)
    }

    @Test func compareMatchesNightVisualBaseline() throws {
        try assertCompare(squat, beside: earlierSquat, choices: [earlierSquat], config: .workoutVisualBaselineNight)
    }

    @Test func compareOfTheLongestSetsMatchesVisualBaseline() throws {
        try assertCompare(longest, beside: otherBlock, choices: [otherBlock, earlierSquat], config: .workoutVisualBaseline)
    }

    @Test func compareWithNothingBesideItMatchesVisualBaseline() {
        let view = FormClipCompareEmpty(name: "Back Squat", onAdd: { _ in }, onClose: {})
            .formClipRoom()
            .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
            .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)
        assertImage(of: view, config: .workoutVisualBaseline)
    }

    @Test func storageListMatchesVisualBaseline() throws {
        try assertStorage(holding: allClips, appearance: .day, colorScheme: .light, config: .workoutVisualBaseline)
    }

    @Test func storageListMatchesNightVisualBaseline() throws {
        try assertStorage(holding: allClips, appearance: .night, colorScheme: .dark, config: .workoutVisualBaselineNight)
    }

    @Test func emptyStorageListMatchesVisualBaseline() throws {
        try assertStorage(holding: [], appearance: .day, colorScheme: .light, config: .workoutVisualBaseline)
    }

    @Test func emptyStorageListMatchesNightVisualBaseline() throws {
        try assertStorage(holding: [], appearance: .night, colorScheme: .dark, config: .workoutVisualBaselineNight)
    }

    private var allClips: [FormClip] { [squat, longest, otherBlock] }

    private var squat: FormClip {
        clip(backSquat(week: 1, .pounds(237.5), .six), byteCount: 48_300_000, barPath: barPath(ending: .endOfClip, upTo: 9))
    }

    private var earlierSquat: FormClip {
        clip(backSquat(week: 2, .pounds(225), .seven), byteCount: 61_200_000, barPath: nil)
    }

    private var lostPlate: FormClip {
        clip(backSquat(week: 3, .pounds(237.5), .six), byteCount: 48_300_000, barPath: barPath(ending: .lostPlate, upTo: 4.3))
    }

    /// The longest a Sheet plausibly names an Exercise, with an Unstructured Set Log in the coach's words.
    private var longest: FormClip {
        clip(
            facts(longName, block: "Block 27", week: 12, .unstructured("3x5 with 225, then a grindy double at 245")),
            byteCount: 2_480_000_000,
            barPath: barPath(ending: .endOfClip, upTo: 9)
        )
    }

    private var otherBlock: FormClip {
        clip(
            facts(
                longName,
                block: "Accumulation Block 26",
                week: 11,
                .setLog(SetLog(weight: .pounds(1102.5), reps: 12, rpe: .eightPointFive))
            ),
            byteCount: 512_000,
            barPath: nil
        )
    }

    private var longName: String { "Close Grip Bench Press with Feet Up, 3 Second Pause" }

    private func backSquat(week: Int, _ weight: Weight, _ rpe: RPE) -> FormClipFacts {
        facts("Back Squat", block: "Block 27", week: week, .setLog(SetLog(weight: weight, reps: 5, rpe: rpe)))
    }

    private func facts(_ name: String, block: String, week: Int, _ logged: LoggedValue) -> FormClipFacts {
        FormClipFacts(
            setID: SetCoordinates.ID(
                session: SessionCoordinate(blockTab: block, address: SessionAddress(week: week, day: 1)),
                exercise: .unchecked(name: ExerciseName(entered: name), ordinal: 0),
                setIndex: 1
            ),
            logged: logged
        )
    }

    private func clip(_ facts: FormClipFacts, byteCount: Int64, barPath: BarPath?) -> FormClip {
        let week = facts.setID.session.address.week
        let id = UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", week))") ?? UUID()
        return FormClip(
            id: id,
            spreadsheetId: "FIXTURE",
            setID: facts.setID,
            logged: facts.logged,
            recordedAt: Date(timeIntervalSinceReferenceDate: Double(week)),
            fileName: "\(id.uuidString).mov",
            byteCount: byteCount,
            duration: 9,
            barPath: barPath,
            startMark: barPath == nil ? nil : 0.8
        )
    }

    private func barPath(ending: BarPath.Ending, upTo end: Double) -> BarPath? {
        let tracked = stride(from: 0.0, through: end, by: 1.0 / 30).map { time in
            let depth = (1 - cos(2 * .pi * time / 3)) / 2
            return BarPath.Sample(time: time, x: 0.46 + 0.03 * depth, y: 0.3 + 0.28 * depth)
        }
        return BarPath(tracked: tracked, ending: ending)
    }

    private func frame(at time: Double) throws -> CGImage {
        let size = CGSize(width: 360, height: 640)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let depth = (1 - cos(2 * .pi * time / 3)) / 2
        let plate = CGPoint(x: size.width * (0.46 + 0.03 * depth), y: size.height * (0.3 + 0.28 * depth))
        let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let context = renderer.cgContext
            context.setFillColor(UIColor(red: 0.84, green: 0.85, blue: 0.81, alpha: 1).cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            context.setFillColor(UIColor(red: 0.59, green: 0.6, blue: 0.56, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: size.height * 0.86, width: size.width, height: size.height * 0.14))
            context.setFillColor(UIColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1).cgColor)
            context.fillEllipse(in: CGRect(x: plate.x - 54, y: plate.y - 54, width: 108, height: 108))
            context.setFillColor(UIColor(red: 0.77, green: 0.78, blue: 0.75, alpha: 1).cgColor)
            context.fillEllipse(in: CGRect(x: plate.x - 16, y: plate.y - 16, width: 32, height: 32))
        }
        return try #require(image.cgImage)
    }

    private func library(holding clips: [FormClip]) throws -> FormClipLibrary {
        let directory = URL.temporaryDirectory.appending(path: "Form Clips \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        for clip in clips {
            try encoder.encode(clip).write(to: directory.appending(path: "\(clip.id.uuidString).json"))
            try Data().write(to: directory.appending(path: clip.fileName))
        }
        return FormClipLibrary(directory: directory, tracker: VisionBarPathTracker(), now: Date.init)
    }

    private func assertCard(
        holding clips: [FormClip],
        appearance: Theme.Appearance,
        colorScheme: ColorScheme,
        config: ViewImageConfig,
        testName: String = #function
    ) throws {
        let scenario = try WorkoutScenarios.freshConfiguredApp()
        VisualFixtureRetainer.retain(scenario)
        let exercise = Exercise(name: "Back Squat", coachNote: nil, order: 0)
        let set = ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE 6", percentOneRM: nil, state: .logged)
        set.setLog = SetLog(weight: .pounds(237.5), reps: 5, rpe: .six)
        exercise.sets = [set]

        let palette = Theme.palette(for: appearance)
        let view = ZStack {
            palette.paperBackground.ignoresSafeArea()
            ActiveSetCard(
                set: set,
                setOrdinal: 2,
                setCount: 5,
                mode: .reviewingLogged(showsSavedConfirmation: false),
                mic: SetCardMic(
                    dictation: .ready,
                    startsHandsFree: false,
                    start: {},
                    shows: { _ in },
                    finish: { nil },
                    listenHandsFree: { nil },
                    cancel: {},
                    dismiss: {}
                ),
                clips: SetCardClipControl(
                    clips: SetCardClips(target: FormClipTarget(squat), clips: clips, isAdding: false),
                    add: { _ in },
                    open: { _ in }
                ),
                onLog: { _ in },
                onSkip: {},
                onDelete: {},
                onTouchWhileHeld: {},
                onClearMenuOpened: {},
                onClearMenuClosed: {}
            )
            .padding(.horizontal, Theme.pageMargin)
        }
        .environment(LastPerformedLookupStore(context: scenario.context))
        .environment(\.themePalette, palette)
        .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
        .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)
        .preferredColorScheme(colorScheme)

        assertImage(of: view, config: config, testName: testName)
        withExtendedLifetime(exercise) {}
    }

    private func assertReview(
        of clip: FormClip,
        among count: Int,
        at time: Double,
        config: ViewImageConfig,
        testName: String = #function
    ) throws {
        let view = FormClipReviewScreen(
            clip: clip,
            facts: clip.snapshotFacts,
            player: ClipPlayer(still: try frame(at: time), time: time, duration: clip.duration, rate: .half, isPlaying: false),
            position: FormClipPosition(of: clip.id, in: (1..<count).map { _ in UUID() } + [clip.id]),
            onClose: {},
            onNext: { _ in },
            onAdd: { _ in }
        )
        .formClipRoom()
        .environment(try library(holding: [clip]))
        .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
        .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)

        assertImage(of: view, config: config, testName: testName)
    }

    private func assertCompare(
        _ left: FormClip,
        beside right: FormClip,
        choices: [FormClip],
        config: ViewImageConfig,
        testName: String = #function
    ) throws {
        let scenario = try WorkoutScenarios.freshConfiguredApp()
        VisualFixtureRetainer.retain(scenario)
        let view = FormClipCompareScreen(
            left: left,
            right: right,
            leftFacts: left.snapshotFacts,
            rightFacts: right.snapshotFacts,
            comparison: ClipComparison(
                left: ClipPlayer(still: try frame(at: 2.1), time: 2.1, duration: left.duration, rate: .half, isPlaying: false),
                right: ClipPlayer(still: try frame(at: 1.3), time: 1.3, duration: right.duration, rate: .half, isPlaying: false),
                leftStart: left.effectiveStart,
                rightStart: right.effectiveStart
            ),
            choices: choices,
            onChoose: { _ in },
            onClose: {}
        )
        .formClipRoom()
        .environment(try library(holding: [left, right]))
        .environment(scenario.store)
        .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
        .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)

        assertImage(of: view, config: config, testName: testName)
    }

    private func assertStorage(
        holding clips: [FormClip],
        appearance: Theme.Appearance,
        colorScheme: ColorScheme,
        config: ViewImageConfig,
        testName: String = #function
    ) throws {
        let scenario = try WorkoutScenarios.freshConfiguredApp()
        VisualFixtureRetainer.retain(scenario)
        let view = NavigationStack { FormClipStorageList() }
            .environment(try library(holding: clips))
            .environment(scenario.store)
            .environment(\.themePalette, Theme.palette(for: appearance))
            .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
            .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)
            .preferredColorScheme(colorScheme)

        assertImage(of: view, config: config, testName: testName)
    }

    private func assertImage(of view: some View, config: ViewImageConfig, testName: String = #function) {
        assertSnapshot(
            of: view,
            as: .image(precision: WorkoutVisualBaseline.labelAntialiasingPrecision, layout: .device(config: config)),
            testName: testName
        )
    }
}
