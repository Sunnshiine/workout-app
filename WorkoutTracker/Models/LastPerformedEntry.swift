import Foundation
import SwiftData

@Model
final class LastPerformedEntry {
    @Attribute(.unique) var fullName: String
    var baseName: String
    var result: SetLog?
    var resultText: String?
    var performedOn: Date
    var source: String

    var displayResultText: String {
        resultText ?? result?.formatted ?? ""
    }

    init(fullName: String, baseName: String, result: SetLog, performedOn: Date, source: String) {
        self.fullName = fullName
        self.baseName = baseName
        self.result = result
        self.resultText = nil
        self.performedOn = performedOn
        self.source = source
    }

    init(fullName: String, baseName: String, resultText: String, performedOn: Date, source: String) {
        self.fullName = fullName
        self.baseName = baseName
        self.result = nil
        self.resultText = resultText
        self.performedOn = performedOn
        self.source = source
    }
}
