import Foundation
import SwiftData

@MainActor
struct LastPerformedIndex {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func lookup(exerciseName: String, baseName: String) -> LastPerformedEntry? {
        let exactDescriptor = FetchDescriptor<LastPerformedEntry>(
            predicate: #Predicate { $0.fullName == exerciseName }
        )
        if let exact = try? context.fetch(exactDescriptor).first {
            return exact
        }

        let fallbackDescriptor = FetchDescriptor<LastPerformedEntry>(
            predicate: #Predicate { $0.baseName == baseName },
            sortBy: [SortDescriptor(\.performedOn, order: .reverse)]
        )
        return try? context.fetch(fallbackDescriptor).first
    }

    func ingest(_ entries: [LastPerformedEntry]) throws {
        for entry in entries {
            if let existing = existingEntry(fullName: entry.fullName) {
                if entry.performedOn >= existing.performedOn {
                    existing.baseName = entry.baseName
                    existing.result = entry.result
                    existing.resultText = entry.resultText
                    existing.performedOn = entry.performedOn
                    existing.source = entry.source
                }
            } else {
                context.insert(entry)
            }
        }
        try context.save()
    }

    private func existingEntry(fullName: String) -> LastPerformedEntry? {
        let descriptor = FetchDescriptor<LastPerformedEntry>(
            predicate: #Predicate { $0.fullName == fullName }
        )
        return try? context.fetch(descriptor).first
    }
}
