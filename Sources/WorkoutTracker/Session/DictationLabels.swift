import Foundation

extension DictationRecord {
    /// What the Set a press wrote held when its records were exported. The same Set Log means the
    /// write stood, another means the athlete corrected it, and Pending means they cleared it.
    struct Label: Equatable, Sendable {
        let record: UUID
        let state: SetState
        /// The Set Log, structured or not, of a Logged Set. Nil otherwise.
        let setLog: String?

        init(record: UUID, holding set: ExerciseSet) {
            let token = SetLogToken.serialize(
                SetLogToken.Classification(state: set.state, setLog: set.setLog, unstructuredSetLog: set.unstructuredSetLog)
            )
            self.record = record
            state = set.state
            setLog = set.state == .logged ? token : nil
        }

        /// What the athlete meant the press to write. Nil for a Set they cleared and left Pending,
        /// which says the write was not wanted but not what was.
        var truth: DictationScoring.Truth? {
            switch state {
            case .logged: setLog.map { .write(.setLog($0)) }
            case .skipped: .write(.skip)
            case .pending: nil
            }
        }
    }
}

/// The labels an export writes beside its Dictation Records, `labels.json`: one for each record
/// whose outcome wrote a Set the cached Block still holds. A Set that is gone has none.
struct DictationLabels: Equatable, Sendable {
    static let schema = 1
    static let fileName = "labels.json"

    let labels: [DictationRecord.Label]

    /// Each label by the record it labels.
    var byRecord: [UUID: DictationRecord.Label] {
        Dictionary(labels.map { ($0.record, $0) }) { first, _ in first }
    }
}

extension DictationLabels: Codable {
    private enum CodingKeys: String, CodingKey {
        case schema, labels
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(Int.self, forKey: .schema)
        guard schema == Self.schema else {
            let description = "Labels schema \(schema) is not \(Self.schema)"
            throw DecodingError.dataCorruptedError(forKey: .schema, in: container, debugDescription: description)
        }
        labels = try container.decode([DictationRecord.Label].self, forKey: .labels)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schema, forKey: .schema)
        try container.encode(labels, forKey: .labels)
    }
}

extension DictationRecord.Label: Codable {
    private enum CodingKeys: String, CodingKey {
        case record, state, setLog
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        record = try container.decode(UUID.self, forKey: .record)
        state = try container.decode(SetState.self, forKey: .state)
        setLog = try container.decodeIfPresent(String.self, forKey: .setLog)
        guard (state == .logged) == (setLog != nil) else {
            let description = "A \(state.rawValue) Set \(setLog == nil ? "needs" : "holds no") Set Log"
            throw DecodingError.dataCorruptedError(forKey: .setLog, in: container, debugDescription: description)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(record, forKey: .record)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(setLog, forKey: .setLog)
    }
}

extension WorkoutApplication {
    /// A label for each record whose outcome wrote a Set, read from the cached Block as it stands.
    func labels(for records: [DictationRecord]) -> DictationLabels {
        DictationLabels(
            labels: records.compactMap { record in
                guard let decided = record.decided, decided.decision.outcome.written != nil, let dictated = decided.set.set,
                    let set = heldSet(dictated)
                else { return nil }
                return DictationRecord.Label(record: record.id, holding: set)
            }
        )
    }

    /// The Set a press was for, if the cached Block is still the one it was in and the Exercise
    /// at its address is still the one it named.
    private func heldSet(_ dictated: DictatedSet) -> ExerciseSet? {
        guard workout.block?.tabName == dictated.block, let set = try? resolveSet(dictated.address) else { return nil }
        return set.exercise?.name == dictated.exercise ? set : nil
    }
}
