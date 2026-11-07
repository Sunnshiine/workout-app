import Foundation
import Testing

@testable import WorkoutTracker

private struct StubTracker: BarPathTracker {
    let result: Result<BarPath, BarPathTraceError>

    func trace(_ movie: URL, from start: BarPathStart, progress: @escaping @Sendable (Double) -> Void) async throws -> BarPath {
        progress(1)
        return try result.get()
    }
}

private func stubPath() throws -> BarPath {
    try #require(
        BarPath(
            tracked: [BarPath.Sample(time: 0, x: 0.5, y: 0.3), BarPath.Sample(time: 1, x: 0.5, y: 0.6)],
            ending: .endOfClip
        )
    )
}

/// A real application over the fresh-block workbook, its first Set Logged, with its Form Clips in a
/// directory this test can read.
@MainActor
private struct Harness {
    let app: WorkoutApplication
    let directory: URL
    let address = SetAddress(exercise: ExerciseAddress(session: SessionAddress(week: 1, day: 1), order: 0), index: 0)

    init() async throws {
        directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        app = try WorkoutApplication(
            environment: .inMemory(
                sheets: LocalWorkbookSheetsClient(workbook: WorkbookScenario.freshBlock.workbook()),
                formClips: directory,
                now: { Date(timeIntervalSince1970: 1_780_000_000) }
            )
        )
        _ = try await app.selectSpreadsheet(id: "FIXTURE", title: nil)
        _ = try app.log(address, setLog: "185x5@8")
    }

    var target: FormClipTarget {
        get throws { try #require(FormClipTarget(try app.resolveSet(address), spreadsheetId: "FIXTURE")) }
    }

    func movie() async throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
        try await SyntheticMovie.write(to: url, frames: 6) { _ in SyntheticMovie.Point(x: 0.5, y: 0.5) }
        return url
    }

    func files() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    func reopened(tracker: any BarPathTracker = VisionBarPathTracker()) -> FormClipLibrary {
        FormClipLibrary(directory: directory, tracker: tracker, now: Date.init)
    }
}

@MainActor
@Suite struct FormClipLibraryTests {
    @Test func anAddedClipMovesInAndIsThereOnTheNextLaunch() async throws {
        let harness = try await Harness()
        let movie = try await harness.movie()

        let clip = try await harness.app.formClips.add(moving: movie, to: try harness.target)

        #expect(!FileManager.default.fileExists(atPath: movie.path))
        #expect(clip.duration > 0)
        #expect(clip.byteCount > 0)
        #expect(clip.fileName.hasSuffix(".mov"))
        #expect(clip.snapshotFacts.logged == .setLog(SetLog(weight: .pounds(185), reps: 5, rpe: .eight)))
        #expect(try harness.files() == ["\(clip.id.uuidString).json", "\(clip.id.uuidString).mov"])

        #expect(harness.reopened().clips == [clip])
    }

    @Test func aSetCanHoldMoreThanOneClip() async throws {
        let harness = try await Harness()
        let target = try harness.target

        let first = try await harness.app.formClips.add(moving: try await harness.movie(), to: target)
        let second = try await harness.app.formClips.add(moving: try await harness.movie(), to: target)

        let onSet = harness.app.formClips.clips(on: target.setID, in: "FIXTURE")
        #expect(Set(onSet.map(\.id)) == [first.id, second.id])
    }

    @Test func aShareSendsTheMovieUnderANameACoachCanReadAndLeavesNoOldLinkBehind() async throws {
        let harness = try await Harness()
        let target = try harness.target
        let clip = try await harness.app.formClips.add(moving: try await harness.movie(), to: target)
        let facts = clip.facts(in: harness.app.workout.block)

        let first = try harness.app.formClips.shareableFile(of: clip, facts: facts)
        let second = try harness.app.formClips.shareableFile(of: clip, facts: facts)

        #expect(second.lastPathComponent == "Back Squat W1 D1 Set 1.mov")
        #expect(first == second)
        #expect(try Data(contentsOf: second) == Data(contentsOf: harness.app.formClips.url(of: clip)))
        let folder = second.deletingLastPathComponent()
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == [second.lastPathComponent])
        #expect(try harness.files().count == 2)
    }

    @Test func anotherSheetsSetOfTheSameCoordinatesHoldsNoneOfThem() async throws {
        let harness = try await Harness()
        let target = try harness.target
        _ = try await harness.app.formClips.add(moving: try await harness.movie(), to: target)

        #expect(harness.app.formClips.clips(on: target.setID, in: "ANOTHER SHEET").isEmpty)
    }

    @Test func aFileWithNoVideoIsRefusedAndStaysWhereItWas() async throws {
        let harness = try await Harness()
        let notAMovie = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
        try Data("not a movie".utf8).write(to: notAMovie)

        await #expect(throws: FormClipError.notAMovie) {
            try await harness.app.formClips.add(moving: notAMovie, to: try harness.target)
        }

        #expect(FileManager.default.fileExists(atPath: notAMovie.path))
        #expect(harness.app.formClips.clips.isEmpty)
    }

    @Test func deletingTakesTheMovieAndItsRecord() async throws {
        let harness = try await Harness()
        let library = harness.app.formClips
        let clip = try await library.add(moving: try await harness.movie(), to: try harness.target)

        try library.delete(clip.id)

        #expect(library.clips.isEmpty)
        #expect(try harness.files().isEmpty)
        #expect(harness.reopened().clips.isEmpty)
        try library.delete(clip.id)
    }

    @Test func aMovieLeftWithNoRecordIsCleanedUpSoStorageStaysTrue() async throws {
        let harness = try await Harness()
        let library = harness.app.formClips
        let clip = try await library.add(moving: try await harness.movie(), to: try harness.target)
        try Data("left behind by a crash".utf8).write(to: harness.directory.appending(path: "\(UUID().uuidString).mov"))

        #expect(harness.reopened().clips == [clip])
        #expect(try harness.files().count == 2)
    }

    @Test func aDamagedRecordCostsOneClipAndKeepsItsMovie() async throws {
        let harness = try await Harness()
        let library = harness.app.formClips
        let kept = try await library.add(moving: try await harness.movie(), to: try harness.target)
        let damaged = try await library.add(moving: try await harness.movie(), to: try harness.target)
        try Data("{".utf8).write(to: harness.directory.appending(path: "\(damaged.id.uuidString).json"))

        #expect(harness.reopened().clips == [kept])
        #expect(try harness.files().contains(damaged.fileName))
    }

    @Test func clipsStayOutOfBackups() async throws {
        let harness = try await Harness()
        _ = try await harness.app.formClips.add(moving: try await harness.movie(), to: try harness.target)

        let values = try harness.directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func aTracedPathAndAStartMarkLastAcrossLaunches() async throws {
        let harness = try await Harness()
        let clip = try await harness.app.formClips.add(moving: try await harness.movie(), to: try harness.target)
        let library = harness.reopened(tracker: StubTracker(result: .success(try stubPath())))

        try await library.traceBarPath(on: clip.id, from: BarPathStart(time: 0, x: 0.5, y: 0.3)) { _ in }
        try library.setStartMark(1.5, on: clip.id)

        let again = try #require(harness.reopened().clip(clip.id))
        #expect(again.barPath == (try stubPath()))
        #expect(again.effectiveStart == 1.5)
    }

    @Test func aFailedTraceLeavesTheClipAsItWas() async throws {
        let harness = try await Harness()
        let clip = try await harness.app.formClips.add(moving: try await harness.movie(), to: try harness.target)
        let library = harness.reopened(tracker: StubTracker(result: .failure(.nothingFollowed)))

        await #expect(throws: BarPathTraceError.nothingFollowed) {
            try await library.traceBarPath(on: clip.id, from: BarPathStart(time: 0, x: 0.5, y: 0.3)) { _ in }
        }

        #expect(library.clip(clip.id)?.barPath == nil)
    }

    @Test func storageReportsEveryClipsSizeAndTheTotal() async throws {
        let harness = try await Harness()
        let library = harness.app.formClips
        let first = try await library.add(moving: try await harness.movie(), to: try harness.target)
        let second = try await library.add(moving: try await harness.movie(), to: try harness.target)

        let storage = FormClipStorage(library.clips, in: harness.app.workout.block)

        #expect(storage.count == 2)
        #expect(Set(storage.rows.map(\.id)) == [first.id, second.id])
        #expect(storage.rows.allSatisfy { $0.name == "Back Squat" && $0.line.hasPrefix("W1 D1 · Set 1") && !$0.size.isEmpty })
        #expect(!storage.total.isEmpty)
    }

    @Test func noClipsReadsAsNothing() {
        let storage = FormClipStorage([], in: nil)

        #expect(storage.rows.isEmpty)
    }
}

/// The Sheet stays the coach's: nothing a clip does reaches it.
@MainActor
@Suite struct FormClipSheetTests {
    @Test func noClipVerbQueuesAWriteOrChangesTheSetLog() async throws {
        let harness = try await Harness()
        let app = harness.app
        _ = try await app.flush()
        let before = try await app.sheet(tab: nil)
        let movie = try await harness.movie()

        let added = try await app.addFormClip(copying: movie, at: harness.address)
        _ = try app.markStart(of: added.id, at: 0.1)
        _ = try await app.traceBarPath(on: added.id, from: BarPathStart(time: 0, x: 0.5, y: 0.5))
        _ = try app.deleteFormClip(added.id)

        #expect(try app.snapshot().pendingWriteCount == 0)
        let after = try await app.sheet(tab: nil)
        #expect(after == before)
    }

    @Test func aSyncReplacingTheBlockLeavesEveryClipOnItsSet() async throws {
        let harness = try await Harness()
        let app = harness.app
        let added = try await app.addFormClip(copying: try await harness.movie(), at: harness.address)
        _ = try await app.flush()

        _ = try await app.sync()

        #expect(try app.formClips(at: harness.address).map(\.id) == [added.id])
    }
}

@MainActor
@Suite struct FormClipFactsTests {
    @Test func aCorrectedSetLogReachesTheCaption() async throws {
        let harness = try await Harness()
        let app = harness.app
        let added = try await app.addFormClip(copying: try await harness.movie(), at: harness.address)
        #expect(added.caption == "Back Squat · W1 D1 · Set 1 · 185×5 @8")

        _ = try app.log(harness.address, setLog: "190x5@8")

        let reread = try #require(try app.formClips(at: harness.address).first)
        #expect(reread.caption == "Back Squat · W1 D1 · Set 1 · 190×5 @8")
        #expect(reread.setLogSnapshot == "185×5 @8")
    }

    @Test func aClearedSetKeepsTheFactsItWasFilmedWith() async throws {
        let harness = try await Harness()
        let app = harness.app
        let added = try await app.addFormClip(copying: try await harness.movie(), at: harness.address)

        _ = try app.deleteLog(harness.address)

        let reread = try #require(try app.formClips(at: harness.address).first { $0.id == added.id })
        #expect(reread.caption == "Back Squat · W1 D1 · Set 1 · 185×5 @8")
    }

    @Test func aPendingSetTakesNoClip() async throws {
        let harness = try await Harness()
        let pending = SetAddress(exercise: harness.address.exercise, index: 1)

        await #expect(throws: ApplicationError.setNotLogged(pending.description)) {
            try await harness.app.addFormClip(copying: try await harness.movie(), at: pending)
        }
    }

    @Test func aSkippedSetTakesNoClip() async throws {
        let harness = try await Harness()
        let skipped = SetAddress(exercise: harness.address.exercise, index: 1)
        _ = try harness.app.skip(skipped)

        await #expect(throws: ApplicationError.setNotLogged(skipped.description)) {
            try await harness.app.addFormClip(copying: try await harness.movie(), at: skipped)
        }
    }

    @Test func aFileThatIsNoMovieIsAnErrorThatNamesIt() async throws {
        let harness = try await Harness()
        let notAMovie = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
        try Data("not a movie".utf8).write(to: notAMovie)

        await #expect(throws: ApplicationError.notAMovie(notAMovie.path)) {
            try await harness.app.addFormClip(copying: notAMovie, at: harness.address)
        }
    }

    @Test func anUnknownClipNamesWhatTheDeviceHolds() async throws {
        let harness = try await Harness()
        let added = try await harness.app.addFormClip(copying: try await harness.movie(), at: harness.address)
        let unknown = UUID()

        #expect(throws: ApplicationError.unknownFormClip(unknown.uuidString, candidates: [added.id.uuidString])) {
            try harness.app.deleteFormClip(unknown)
        }
    }
}
