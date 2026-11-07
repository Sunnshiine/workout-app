import Foundation

/// What Form Clips take on this phone, for the row that lets the athlete see and free it.
struct FormClipStorage: Equatable, Sendable {
    struct Row: Equatable, Identifiable, Sendable {
        let id: UUID
        let name: String
        let line: String
        let size: String
    }

    let total: String
    let count: Int
    /// Newest first, as the library holds them.
    let rows: [Row]

    @MainActor
    init(_ clips: [FormClip], in block: Block?) {
        total = Self.size(clips.reduce(0) { $0 + $1.byteCount })
        count = clips.count
        rows = clips.map { clip in
            let facts = clip.facts(in: block)
            return Row(id: clip.id, name: facts.exerciseName, line: facts.line, size: Self.size(clip.byteCount))
        }
    }

    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
