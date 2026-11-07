import Foundation

/// One Form Clip, as a verb reports it.
public struct FormClipReport: Encodable, Equatable, Sendable {
    public let id: UUID
    /// `Block 27 · W1 D1`
    public let session: String
    public let exercise: String
    public let setNumber: Int
    /// The Set Log as it stood when the clip was added.
    public let setLogSnapshot: String
    /// What a share sends, from the Set's current Set Log.
    public let caption: String
    public let recordedAt: Date
    public let file: String
    public let byteCount: Int64
    public let duration: Double
    public let startMark: Double?
    public let barPath: BarPath?
}

/// What Form Clips take on this device.
public struct FormClipStorageReport: Encodable, Equatable, Sendable {
    public let count: Int
    public let byteCount: Int64
    public let total: String
    public let clips: [FormClipReport]
}

extension WorkoutApplication {
    /// The app's Add Clip, on a copy, so the CLI's own file stays where it was. It writes nothing to
    /// the Sheet. A Set that is not Logged takes no clip.
    public func addFormClip(copying movie: URL, at address: SetAddress) async throws -> FormClipReport {
        let set = try resolveSet(address)
        guard let spreadsheetId = settings.spreadsheetId else { throw ApplicationError.notConfigured }
        guard let target = FormClipTarget(set, spreadsheetId: spreadsheetId) else {
            throw ApplicationError.setNotLogged(address.description)
        }
        let copy = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).\(movie.pathExtension)")
        do {
            try FileManager.default.copyItem(at: movie, to: copy)
            return report(on: try await formClips.add(moving: copy, to: target))
        } catch FormClipError.notAMovie {
            try? FileManager.default.removeItem(at: copy)
            throw ApplicationError.notAMovie(movie.path)
        } catch is CocoaError {
            throw ApplicationError.notAMovie(movie.path)
        }
    }

    /// Newest first, on `address` when one is given.
    public func formClips(at address: SetAddress?) throws -> [FormClipReport] {
        guard let address else { return formClips.clips.map(report(on:)) }
        guard let spreadsheetId = settings.spreadsheetId else { throw ApplicationError.notConfigured }
        let coordinates = try SetCoordinates(of: try resolveSet(address))
        return formClips.clips(on: coordinates.id, in: spreadsheetId).map(report(on:))
    }

    public func deleteFormClip(_ id: UUID) throws -> FormClipStorageReport {
        _ = try resolveClip(id)
        try formClips.delete(id)
        return formClipStorage()
    }

    /// The tap on the plate, then the path the tracker follows from it, kept on the clip.
    public func traceBarPath(on id: UUID, from start: BarPathStart) async throws -> FormClipReport {
        _ = try resolveClip(id)
        do {
            try await formClips.traceBarPath(on: id, from: start) { _ in }
        } catch BarPathTraceError.nothingFollowed {
            throw ApplicationError.barPathNotFollowed(id.uuidString)
        }
        return report(on: try resolveClip(id))
    }

    /// Marks where the Set starts, to line the clip up in a Compare. Nil clears the mark.
    public func markStart(of id: UUID, at time: Double?) throws -> FormClipReport {
        _ = try resolveClip(id)
        try formClips.setStartMark(time, on: id)
        return report(on: try resolveClip(id))
    }

    /// The clip a Compare opens beside `id`, or nil when it is the only one of its Movement.
    public func previousFormClip(of id: UUID) throws -> FormClipReport? {
        formClips.previous(of: try resolveClip(id)).map(report(on:))
    }

    public func formClipStorage() -> FormClipStorageReport {
        let clips = formClips.clips
        let byteCount = clips.reduce(0) { $0 + $1.byteCount }
        return FormClipStorageReport(
            count: clips.count,
            byteCount: byteCount,
            total: FormClipStorage(clips, in: workout.block).total,
            clips: clips.map(report(on:))
        )
    }

    private func resolveClip(_ id: UUID) throws -> FormClip {
        guard let clip = formClips.clip(id) else {
            throw ApplicationError.unknownFormClip(id.uuidString, candidates: formClips.clips.map(\.id.uuidString))
        }
        return clip
    }

    private func report(on clip: FormClip) -> FormClipReport {
        FormClipReport(
            id: clip.id,
            session: clip.setID.session.storageValue,
            exercise: clip.setID.exercise.name.entered,
            setNumber: clip.setID.setIndex + 1,
            setLogSnapshot: clip.snapshotFacts.logged.label,
            caption: clip.facts(in: workout.block).caption,
            recordedAt: clip.recordedAt,
            file: formClips.url(of: clip).path,
            byteCount: clip.byteCount,
            duration: clip.duration,
            startMark: clip.startMark,
            barPath: clip.barPath
        )
    }
}
