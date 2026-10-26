import SwiftData

@Model
final class ModelHeldAcrossReload {
    func relationshipInModelsPasses() {}
    var week: Week?

    init() {}
}
