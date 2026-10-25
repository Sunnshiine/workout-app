import Foundation
import MetricKit
import os

/// Hands every payload MetricKit delivers to the Dictation Records' journal, so an export carries
/// the hangs, memory, and exits iOS measured. Payloads arrive up to a day after the fact, and never
/// in the Simulator.
final class DictationMetricKit: NSObject, MXMetricManagerSubscriber {
    private let journal: DictationJournal

    init(journal: DictationJournal) {
        self.journal = journal
        super.init()
        MXMetricManager.shared.add(self)
    }

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            journal.keep(MetricKitPayload(kind: .metrics, endedAt: payload.timeStampEnd, json: payload.jsonRepresentation()))
        }
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            journal.keep(MetricKitPayload(kind: .diagnostics, endedAt: payload.timeStampEnd, json: payload.jsonRepresentation()))
        }
    }
}

/// A window of the Speech Model's work that MetricKit measures on its own, its CPU, memory, and
/// hitches reported per name in the day's metrics.
struct SpeechModelInterval {
    private static let log = MXMetricManager.makeLogHandle(category: "SpeechModel")

    private let name: StaticString
    private let id: OSSignpostID

    init(_ name: StaticString) {
        self.name = name
        id = OSSignpostID(log: Self.log)
        mxSignpost(.begin, log: Self.log, name: name, signpostID: id)
    }

    func end() {
        mxSignpost(.end, log: Self.log, name: name, signpostID: id)
    }
}
