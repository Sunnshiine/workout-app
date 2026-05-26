import Foundation
import SwiftData

@Model
final class LastPerformedEntry {
    @Attribute(.unique) var fullName: String
    var baseName: String
    var result: SetLog
    var performedOn: Date
    var source: String

    init(fullName: String, baseName: String, result: SetLog, performedOn: Date, source: String) {
        self.fullName = fullName
        self.baseName = baseName
        self.result = result
        self.performedOn = performedOn
        self.source = source
    }
}
