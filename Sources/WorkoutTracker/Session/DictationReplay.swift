import Foundation

/// Recorded presses scored under every `MergeRule`, grouped by the Speech Model version their
/// Recording Transcript was read with, so a change of rule can be judged on real presses before it
/// ships. Each rule's outcome is the one its press recorded in `byRule`.
public struct DictationReplay: Encodable, Equatable, Sendable {
    public struct Version: Encodable, Equatable, Sendable {
        let version: SpeechModelVersion
        let decided: Int
        /// The rule that decided each press as it happened.
        let decidedBy: [String: Int]
        /// Presses an export labelled. Nil without labels.
        let labelled: Int?
        let rules: [String: Rule]
    }

    public struct Rule: Encodable, Equatable, Sendable {
        let outcomes: [String: Int]
        /// Presses this rule decides differently from the rule that decided them, by what each
        /// does to the Set and the card rather than by the words each heard.
        let differsFromDecided: Int
        /// Nil without labels.
        let scored: DictationScore?
    }

    let presses: Int
    let unreadableLines: Int
    let cancelled: Int
    let versions: [Version]
    let caveats: [String]

    static let unlabelled = "No labels were given, so this counts where the rules disagree, not which rule is right."
    static let recorded = "Each rule's outcome is the one recorded at the press, not one today's parser would decide."
}

extension DictationReplay {
    init(_ records: [DictationRecord], unreadableLines: Int, labels: DictationLabels?) {
        let byRecord = labels?.byRecord
        let decided = records.compactMap { record in
            record.decided.map { Press(decided: $0, label: byRecord?[record.id]) }
        }
        var versions: [SpeechModelVersion] = []
        for press in decided where !versions.contains(press.decided.recording.version) {
            versions.append(press.decided.recording.version)
        }
        presses = records.count
        self.unreadableLines = unreadableLines
        cancelled = records.count - decided.count
        self.versions = versions.map { version in
            Version(version, presses: decided.filter { $0.decided.recording.version == version }, isLabelled: labels != nil)
        }
        caveats = (labels == nil ? [Self.unlabelled] : DictationScore.caveats) + [Self.recorded]
    }

    fileprivate struct Press {
        let decided: DictationRecord.Decided
        let label: DictationRecord.Label?
    }

    fileprivate static func counts(_ keys: [String]) -> [String: Int] {
        keys.reduce(into: [:]) { counts, key in counts[key, default: 0] += 1 }
    }
}

extension DictationReplay.Version {
    fileprivate init(_ version: SpeechModelVersion, presses: [DictationReplay.Press], isLabelled: Bool) {
        self.init(
            version: version,
            decided: presses.count,
            decidedBy: DictationReplay.counts(presses.map(\.decided.decision.rule.rawValue)),
            labelled: isLabelled ? presses.count { $0.label != nil } : nil,
            rules: Dictionary(
                uniqueKeysWithValues: MergeRule.allCases.map { rule in
                    let decisions = presses.compactMap { press in
                        press.decided.decision.byRule[rule].map { (press: press, outcome: $0) }
                    }
                    let replayed = DictationReplay.Rule(
                        outcomes: DictationReplay.counts(decisions.map(\.outcome.kind.rawValue)),
                        differsFromDecided: decisions.count { !$0.press.decided.decision.outcome.decidesAlike($0.outcome) },
                        scored: isLabelled ? DictationScore(decisions.map { ($0.outcome, $0.press.label?.truth) }) : nil
                    )
                    return (rule.rawValue, replayed)
                }
            )
        )
    }
}

extension DictationRecord.Outcome {
    /// Whether two outcomes do the same to the Set and the card, whatever words each heard.
    func decidesAlike(_ other: Self) -> Bool {
        kind == other.kind && setLog == other.setLog && draft == other.draft && rejection == other.rejection
    }
}
