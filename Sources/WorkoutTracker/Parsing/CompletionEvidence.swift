import Foundation

/// What one Set contributes as completion evidence. A Pending Set contributes `nil`, and so does a
/// Set a Legacy Log marked Logged without the athlete entering anything for it.
enum SetCompletionEvidence: Equatable, Sendable {
    case logged(String)
    case skipped

    var token: String {
        switch self {
        case .logged(let text): text
        case .skipped: SetLogToken.skipSentinel
        }
    }

    var isLogged: Bool {
        if case .logged = self { return true }
        return false
    }
}

extension ParsedSet {
    var completionEvidence: SetCompletionEvidence? {
        if let setLog { return .logged(setLog.formatted) }
        let entered = unstructuredSetLog?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if state == .logged, !entered.isEmpty { return .logged(entered) }
        return state == .skipped ? .skipped : nil
    }
}

/// The one owner of an Exercise's completion evidence. That evidence is the Exercise's Set-level
/// Set Logs in Set order, with the Legacy Log as the fallback used only when the Exercise bears no
/// Set-level evidence at all (CONTEXT.md *Completion Evidence*, ADR-0005).
extension ParsedExercise {
    var setLevelCompletionEvidence: [SetCompletionEvidence] {
        sets.sorted { $0.index < $1.index }.compactMap(\.completionEvidence)
    }

    /// The Exercise bears current Set-level evidence, meaning at least one Set the athlete logged.
    /// A Structured Set Log and an Unstructured Set Log both count, because CONTEXT.md makes the
    /// Unstructured Set Log "Set-level completion evidence, distinct from a Legacy Log". A Skipped
    /// Set does not count, because a skip records that the athlete did not perform the Set.
    var hasSetLevelCompletionEvidence: Bool {
        setLevelCompletionEvidence.contains(where: \.isLogged)
    }

    var legacyLogAsCompletionEvidence: String? {
        hasSetLevelCompletionEvidence ? nil : legacyLog
    }

    /// This Exercise with the Legacy Log's completion clause applied, that a Legacy Log counts all
    /// prescribed Sets for the Exercise complete (CONTEXT.md *Legacy Log*).
    func completingSetsFromLegacyLog() -> ParsedExercise {
        guard legacyLogAsCompletionEvidence != nil else { return self }

        var completed = self
        completed.sets = sets.map { set in
            var completedSet = set
            completedSet.state = set.state == .skipped ? .skipped : .logged
            return completedSet
        }
        return completed
    }
}
