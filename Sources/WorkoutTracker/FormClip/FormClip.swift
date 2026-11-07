import Foundation

/// A movie of one Logged Set, kept on this device alone. It names its Set by the coordinates a
/// sync's re-parse keeps and never holds a model, since a sync replaces every model in the cached
/// Block. Its Movement is matched at query time from the name in `setID` (ADR-0013).
public struct FormClip: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    let spreadsheetId: String
    let setID: SetCoordinates.ID
    /// What the Set said when the clip was added. `facts(in:)` prefers what it says now.
    let logged: LoggedValue
    public let recordedAt: Date
    /// Relative to the library's directory, because the sandbox path changes across installs.
    public let fileName: String
    public let byteCount: Int64
    public let duration: Double
    var barPath: BarPath?  // default: no path, the answer until the athlete taps the plate
    /// Seconds into the movie. Nil starts the clip at its first frame.
    var startMark: Double?  // default: no mark, the answer until the athlete flags a start

    var effectiveStart: Double { startMark ?? 0 }
}

/// What a Logged Set says: a Set Log, or the text of an Unstructured Set Log.
enum LoggedValue: Codable, Equatable, Sendable {
    case setLog(SetLog)
    case unstructured(String)

    @MainActor
    init?(_ set: ExerciseSet) {
        guard set.state == .logged else { return nil }
        if let log = set.setLog {
            self = .setLog(log)
        } else if let text = set.unstructuredSetLog {
            self = .unstructured(text)
        } else {
            return nil
        }
    }

    /// `237.5×5 @6`, the way the Exercise History sheet's chips and the Live Activity read it.
    var label: String {
        switch self {
        case .setLog(let log): "\(log.weight.label)×\(log.reps) @\(log.rpe.label)"
        case .unstructured(let text): text
        }
    }
}

/// The Set a clip is being added to, captured when the athlete asks, so what the card shows next
/// cannot change where the clip lands.
struct FormClipTarget: Equatable, Identifiable, Sendable {
    let spreadsheetId: String
    let setID: SetCoordinates.ID
    let logged: LoggedValue

    var id: SetCoordinates.ID { setID }

    /// Nil for a Set the athlete has not Logged, or one a sync detached.
    @MainActor
    init?(_ set: ExerciseSet, spreadsheetId: String) {
        guard let logged = LoggedValue(set), let coordinates = try? SetCoordinates(of: set) else { return nil }
        self.spreadsheetId = spreadsheetId
        self.setID = coordinates.id
        self.logged = logged
    }

    /// Another clip for the Set `clip` is on, with the facts it was filmed with.
    init(_ clip: FormClip) {
        spreadsheetId = clip.spreadsheetId
        setID = clip.setID
        logged = clip.logged
    }
}

extension FormClip {
    /// What the clip's Set says: its current Set Log while the Block holds it Logged, otherwise the
    /// snapshot, so a corrected Set Log never sends stale facts and a Cleared Set keeps its record.
    @MainActor
    func facts(in block: Block?) -> FormClipFacts {
        let current = block.flatMap { $0.setsByID[setID] }.flatMap(LoggedValue.init)
        return FormClipFacts(setID: setID, logged: current ?? logged)
    }

    var snapshotFacts: FormClipFacts {
        FormClipFacts(setID: setID, logged: logged)
    }
}

/// The words a Form Clip travels with. Only the Base Name reaches the coach, because a Cadence
/// prefix never reads as part of the Exercise's name.
struct FormClipFacts: Equatable, Sendable {
    let setID: SetCoordinates.ID
    let logged: LoggedValue

    /// `Back Squat`, numbered past the first of its name in the Session.
    var exerciseName: String { setID.exercise.athleteLabel }

    /// `W1 D1 · Set 2 · 237.5×5 @6`, which the review shows under the name.
    var line: String {
        "\(setID.session.address.sessionLabel) · Set \(setID.setIndex + 1) · \(logged.label)"
    }

    /// `Back Squat · W1 D1 · Set 2 · 237.5×5 @6`
    var caption: String { "\(exerciseName) · \(line)" }

    /// A file name a coach can read when the movie arrives: `Back Squat W1 D1 Set 2.mov`.
    func shareFileName(extension fileExtension: String) -> String {
        let name = "\(exerciseName) \(setID.session.address.sessionLabel) Set \(setID.setIndex + 1)"
        return "\(name.replacingOccurrences(of: "/", with: "-")).\(fileExtension)"
    }

    /// Which Session and Set a clip beside another shows, with the Block when it is another Block's.
    func placement(beside block: String) -> String {
        let session = setID.session
        let place = "\(session.address.sessionLabel) · Set \(setID.setIndex + 1)"
        return session.blockTab == block ? place : "\(session.blockTab) · \(place)"
    }
}
