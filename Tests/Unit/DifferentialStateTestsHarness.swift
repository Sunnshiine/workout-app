import Foundation
import Testing
import WorkoutTracker

extension DifferentialStateTests {
    enum Operation: Hashable, Sendable, CustomStringConvertible {
        case log(set: SetAddress, setLog: String)
        case skip(SetAddress)
        case deleteLog(SetAddress)
        case view(SessionAddress)
        case makeCurrent
        case requestMoveOn
        case dismissCelebration
        case flush
        case sync
        case coach(cell: String, value: String)

        private static let bareVerbs: [String: Operation] = [
            "make-current": .makeCurrent, "request-move-on": .requestMoveOn, "dismiss-celebration": .dismissCelebration,
            "flush": .flush, "sync": .sync
        ]

        /// After `coach `, up to the first `=` is the cell and the rest is the value, which may be
        /// empty or hold spaces and commas.
        init?(_ text: String) {
            if text.hasPrefix("coach ") {
                let edit = text.dropFirst("coach ".count)
                guard let equals = edit.firstIndex(of: "="), equals != edit.startIndex else { return nil }
                self = .coach(cell: String(edit[..<equals]), value: String(edit[edit.index(after: equals)...]))
                return
            }
            let words = text.split(separator: " ").map(String.init)
            if words.count == 1, let bare = Self.bareVerbs[words[0]] {
                self = bare
                return
            }
            guard words.count >= 2 else { return nil }
            switch (words[0], words.count, SetAddress(words[1]), SessionAddress(words[1])) {
            case ("log", 3, let set?, _): self = .log(set: set, setLog: words[2])
            case ("skip", 2, let set?, _): self = .skip(set)
            case ("delete-log", 2, let set?, _): self = .deleteLog(set)
            case ("view", 2, _, let session?): self = .view(session)
            default: return nil
            }
        }

        var description: String {
            switch self {
            case .log(let set, let setLog): "log \(set) \(setLog)"
            case .skip(let set): "skip \(set)"
            case .deleteLog(let set): "delete-log \(set)"
            case .view(let session): "view \(session)"
            case .coach(let cell, let value): "coach \(cell)=\(value)"
            default: Self.bareVerbs.first { $0.value == self }?.key ?? ""
            }
        }

        var coachCell: String? {
            if case .coach(let cell, _) = self { return cell }
            return nil
        }

        /// A script is `op; op; op`, the line a violation prints.
        static func script(_ text: String) throws -> [Operation] {
            try text.split(separator: ";").map { part in
                let op = part.trimmingCharacters(in: .whitespaces)
                return try #require(Operation(op), "\"\(op)\" is not an op")
            }
        }

        static func line(_ ops: [Operation]) -> String { ops.map(\.description).joined(separator: "; ") }
    }

    @MainActor
    final class Harness {
        private static let now = Date(timeIntervalSince1970: 1_780_000_000)

        private let home: URL
        private let app: WorkoutApplication
        private(set) var executed: [Operation] = []
        private(set) var i1Checks = 0
        private(set) var i2Checks = 0
        private var coachEditedSinceSync = false
        private var coachEditedSinceRequest = false
        private var conflictHighWater: [String: Int] = [:]

        // What the search draws from: the harness's own ops and what the verbs returned, never an
        // extra read of the app, which in end-only mode would be an observation.
        private(set) var setStates: [SetAddress: String] = [:]
        private(set) var viewed: SessionAddress?
        private(set) var current: SessionAddress?
        private(set) var celebrated: SessionAddress?
        let availableSessions: [SessionAddress]

        init() async throws {
            home = try Self.makeHome()
            try WorkbookScenario.freshBlock.workbook().write(to: home.appending(path: "workbook.json"))
            app = try Self.open(home)
            let selected = try await app.selectSpreadsheet(id: "FIXTURE", title: "Fixture Training Log")
            availableSessions = selected.sessions.filter(\.available).map(\.id)
            note(selected)
        }

        deinit { try? FileManager.default.removeItem(at: home) }

        static func run(_ ops: [Operation], observing observation: Observation) async throws -> Violation? {
            let harness = try await Harness()
            for (index, op) in ops.enumerated() {
                if let violation = try await harness.perform(op) { return violation }
                if observation == .everyStep || index == ops.count - 1, let violation = try await harness.observe() {
                    return violation
                }
            }
            return nil
        }

        /// Runs one op with plain `try` and checks I3 and I4. An op that throws is left out of `executed`.
        func perform(_ op: Operation) async throws -> Violation? {
            let coachEditedBefore = coachEditedSinceSync
            let outcome = try await apply(op)
            executed.append(op)
            let refusals = risen(outcome.conflicts)
            if !refusals.isEmpty, !coachEditedBefore { return violation(.refusal, refusals.joined(separator: " | ")) }
            return outcome.backward.map { violation(.backward, $0) }
        }

        private func apply(_ op: Operation) async throws -> (conflicts: [String], backward: String?) {
            switch op {
            case .log(let set, let setLog): setStates[set] = try app.log(set, setLog: setLog).set.state
            case .skip(let set): setStates[set] = try app.skip(set).set.state
            case .deleteLog(let set): setStates[set] = try app.deleteLog(set).set.state
            case .view(let session): note(try app.view(session))
            case .makeCurrent: note(try app.makeCurrent())
            case .requestMoveOn:
                let snapshot = try app.requestMoveOnCelebration()
                note(snapshot)
                celebrated = snapshot.currentSession
                coachEditedSinceRequest = false
            case .dismissCelebration: return ([], try dismiss())
            case .flush: return (try await app.flush().conflictedWrites, nil)
            case .sync:
                let report = try await app.sync()
                (viewed, current) = (report.viewedSession, report.currentSession)
                coachEditedSinceSync = false
                return (report.conflictedWrites, nil)
            case .coach(let cell, let value): try coach(cell, value)
            }
            return ([], nil)
        }

        /// A coach edit and a sync can legitimately move the Current Session, so only a celebration the
        /// coach left alone is held to I4.
        private func dismiss() throws -> String? {
            let held = celebrated
            let coachEdited = coachEditedSinceRequest
            (celebrated, coachEditedSinceRequest) = (nil, false)
            let report = try app.dismissMoveOnCelebration()
            note(report.snapshot)
            guard let held, !coachEdited, let landed = report.snapshot.currentSession,
                (landed.week, landed.day) < (held.week, held.day)
            else { return nil }
            return "celebrated \(held), landed on \(landed)"
        }

        private func coach(_ cell: String, _ value: String) throws {
            let url = home.appending(path: "workbook.json")
            var workbook = try LocalWorkbook.load(from: url)
            workbook.tabs["Block 27"]?.cells[cell] = value.isEmpty ? nil : value
            try workbook.write(to: url)
            coachEditedSinceSync = true
            if celebrated != nil { coachEditedSinceRequest = true }
        }

        /// Every report relists each standing conflict, and two conflicts can share a text, so a
        /// message is new only when its count rises above the most seen at once.
        private func risen(_ conflicts: [String]) -> [String] {
            let counts = Dictionary(conflicts.map { ($0, 1) }, uniquingKeysWith: +)
            let risen = counts.filter { $0.value > conflictHighWater[$0.key, default: 0] }
            conflictHighWater.merge(risen) { _, new in new }
            return risen.keys.sorted()
        }

        private func note(_ snapshot: AppSnapshot) {
            (viewed, current) = (snapshot.viewedSession, snapshot.currentSession)
        }

        /// I1, then I2 when nothing is queued and the coach has not edited since the last sync.
        func observe() async throws -> Violation? {
            i1Checks += 1
            let live = try Self.fingerprint(app, keepingLoggedAt: true)
            if let detail = Self.difference(live, try Self.fingerprint(try Self.open(home), keepingLoggedAt: true), "reopened") {
                return violation(.reopened, detail)
            }
            guard try app.snapshot().pendingWriteCount == 0, !coachEditedSinceSync else { return nil }
            i2Checks += 1
            let other = try Self.makeHome()
            defer { try? FileManager.default.removeItem(at: other) }
            for file in ["workbook.json", "settings.json"] {
                try FileManager.default.copyItem(at: home.appending(path: file), to: other.appending(path: file))
            }
            let resynced = try Self.open(other)
            _ = try await resynced.sync()
            let rederived = try Self.fingerprint(resynced, keepingLoggedAt: false)
            return Self.difference(try Self.fingerprint(app, keepingLoggedAt: false), rederived, "resynced").map {
                violation(.resynced, $0)
            }
        }

        private func violation(_ invariant: Invariant, _ detail: String) -> Violation {
            Violation(invariant: invariant, step: executed.count - 1, op: executed.last!, detail: detail, script: Operation.line(executed))
        }

        private static func makeHome() throws -> URL {
            let home = FileManager.default.temporaryDirectory.appending(path: "differential-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            return home
        }

        private static func open(_ home: URL) throws -> WorkoutApplication {
            let frozen = now
            return try WorkoutApplication(
                environment: .directory(home, workbookFile: home.appending(path: "workbook.json"), now: { frozen })
            )
        }

        /// `snapshot()` and every Session's `session(_:)`, flattened to key path and leaf. The Sync
        /// Outcome and the Viewed Session are transient, and the Sheet does not carry `loggedAt`.
        private static func fingerprint(_ app: WorkoutApplication, keepingLoggedAt: Bool) throws -> [String: String] {
            let dropped: Set<String> = keepingLoggedAt ? ["syncOutcome", "viewedSession"] : ["syncOutcome", "viewedSession", "loggedAt"]
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .sortedKeys
            var leaves: [String: String] = [:]
            func flatten(_ value: Any, at path: String) {
                switch value {
                case let object as [String: Any] where !object.isEmpty:
                    for (key, child) in object where !dropped.contains(key) { flatten(child, at: "\(path).\(key)") }
                case let array as [Any] where !array.isEmpty:
                    for (index, child) in array.enumerated() { flatten(child, at: "\(path)[\(index)]") }
                case is [String: Any]: leaves[path] = "{}"
                case is [Any]: leaves[path] = "[]"
                case is NSNull: leaves[path] = "null"
                default: leaves[path] = "\(value)"
                }
            }
            let snapshot = try app.snapshot()
            flatten(try JSONSerialization.jsonObject(with: try encoder.encode(snapshot)), at: "app")
            for session in snapshot.sessions {
                flatten(try JSONSerialization.jsonObject(with: try encoder.encode(try app.session(session.id))), at: "\(session.id)")
            }
            return leaves
        }

        private static func difference(_ live: [String: String], _ other: [String: String], _ name: String) -> String? {
            guard let path = Set(live.keys).union(other.keys).sorted().first(where: { live[$0] != other[$0] }) else { return nil }
            return "\(path): live \(live[path] ?? "absent"), \(name) \(other[path] ?? "absent")"
        }
    }
}
