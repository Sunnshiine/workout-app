import AVFoundation
import Foundation
import Observation
import os

private let libraryLogger = Logger(subsystem: "WorkoutTracker", category: "FormClipLibrary")

public enum FormClipError: Error, Equatable, Sendable {
    case notAMovie
    case noSuchClip
    case setNotLogged
    case noSheet
}

/// Every Form Clip on this device. Each is a movie and its record, side by side in `directory`, so
/// a damaged record costs one clip, and a sync, which replaces the cached Block, touches none.
/// Nothing here reaches the Sheet.
@MainActor
@Observable
public final class FormClipLibrary {
    /// Newest first.
    public private(set) var clips: [FormClip]
    @ObservationIgnored let directory: URL
    @ObservationIgnored private let tracker: any BarPathTracker
    @ObservationIgnored private let now: @MainActor () -> Date

    init(directory: URL, tracker: any BarPathTracker, now: @escaping @MainActor () -> Date) {
        self.directory = directory
        self.tracker = tracker
        self.now = now
        clips = Self.read(directory)
    }

    func url(of clip: FormClip) -> URL {
        directory.appending(path: clip.fileName)
    }

    func clips(on set: SetCoordinates.ID, in spreadsheetId: String) -> [FormClip] {
        clips.filter { $0.setID == set && $0.spreadsheetId == spreadsheetId }
    }

    /// Moves `movie` in. The movie is read and moved off the main actor, since a long one takes time.
    @discardableResult
    func add(moving movie: URL, to target: FormClipTarget) async throws -> FormClip {
        let id = UUID()
        let directory = directory
        let fileName = "\(id.uuidString).\(movie.pathExtension.isEmpty ? "mov" : movie.pathExtension.lowercased())"
        let filed = try await Self.file(movie, as: fileName, in: directory)
        let clip = FormClip(
            id: id,
            spreadsheetId: target.spreadsheetId,
            setID: target.setID,
            logged: target.logged,
            recordedAt: filed.recordedAt ?? now(),
            fileName: fileName,
            byteCount: filed.byteCount,
            duration: filed.duration,
            barPath: nil,
            startMark: nil
        )
        do {
            try write(clip)
        } catch {
            try? FileManager.default.removeItem(at: directory.appending(path: fileName))
            throw error
        }
        clips.insert(clip, at: 0)
        clips.sort { $0.recordedAt > $1.recordedAt }
        return clip
    }

    /// Removes the movie and its record. Removing a clip already gone converges.
    func delete(_ id: UUID) throws {
        guard let clip = clips.first(where: { $0.id == id }) else { return }
        try Self.removeIfPresent(url(of: clip))
        try Self.removeIfPresent(recordURL(of: id))
        clips.removeAll { $0.id == id }
    }

    /// Follows the plate from `start` and keeps the path on the clip, replacing any it held. A
    /// cancelled or failed trace leaves the clip as it was.
    @discardableResult
    func traceBarPath(
        on id: UUID,
        from start: BarPathStart,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> BarPath {
        guard let clip = clip(id) else { throw FormClipError.noSuchClip }
        let path = try await tracker.trace(url(of: clip), from: start, progress: progress)
        try update(id) { $0.barPath = path }
        return path
    }

    func setStartMark(_ time: Double?, on id: UUID) throws {
        try update(id) { $0.startMark = time }
    }

    func clip(_ id: UUID) -> FormClip? {
        clips.first { $0.id == id }
    }

    /// A link to the movie under a name a coach can read, in a folder emptied on each share so
    /// old links never add up to storage the athlete cannot see.
    func shareableFile(of clip: FormClip, facts: FormClipFacts) throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "Form Clip Share")
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: facts.shareFileName(extension: url(of: clip).pathExtension))
        try FileManager.default.linkItem(at: url(of: clip), to: file)
        return file
    }

    private func update(_ id: UUID, _ change: (inout FormClip) -> Void) throws {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { throw FormClipError.noSuchClip }
        var changed = clips[index]
        change(&changed)
        try write(changed)
        clips[index] = changed
    }

    private func recordURL(of id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }

    private func write(_ clip: FormClip) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(clip).write(to: recordURL(of: clip.id), options: .atomic)
    }

    private static func removeIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private struct Filed: Sendable {
        let recordedAt: Date?
        let byteCount: Int64
        let duration: Double
    }

    /// Refuses a file with no video before it moves, so a bad pick leaves nothing behind. The
    /// directory stays out of backups, so a clip never leaves the phone that way either.
    private nonisolated static func file(_ movie: URL, as fileName: String, in directory: URL) async throws -> Filed {
        let asset = AVURLAsset(url: movie)
        guard
            let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty,
            let duration = try? await asset.load(.duration).seconds, duration > 0
        else { throw FormClipError.notAMovie }
        let created = try? await asset.load(.creationDate)
        let recordedAt = try? await created?.load(.dateValue)

        var folder = directory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        let destination = directory.appending(path: fileName)
        try FileManager.default.moveItem(at: movie, to: destination)
        let byteCount = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        return Filed(recordedAt: recordedAt, byteCount: Int64(byteCount), duration: duration)
    }

    /// Reads every record, then drops what a crash between the movie's move and its record's write
    /// left behind. A record that fails to decode keeps its movie, since a later build may read it.
    private static func read(_ directory: URL) -> [FormClip] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = names.filter { $0.hasSuffix(".json") }
        let clips = records.compactMap { name -> FormClip? in
            do {
                let clip = try decoder.decode(FormClip.self, from: Data(contentsOf: directory.appending(path: name)))
                return names.contains(clip.fileName) ? clip : nil
            } catch {
                libraryLogger.error("Form Clip record \(name, privacy: .public) was not read: \(error, privacy: .public)")
                return nil
            }
        }
        removeMovies(in: directory, among: names, withNoRecordIn: records)
        return clips.sorted { $0.recordedAt > $1.recordedAt }
    }

    private static func removeMovies(in directory: URL, among names: [String], withNoRecordIn records: [String]) {
        let recorded = Set(records.map { $0.dropLast(".json".count) })
        for name in names where !name.hasSuffix(".json") && !recorded.contains(name.prefix { $0 != "." }) {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }
}
