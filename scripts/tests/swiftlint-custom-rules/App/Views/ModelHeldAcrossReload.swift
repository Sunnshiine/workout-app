import SwiftUI

struct ModelHeldAcrossReload: View {
    @State private var historyExercise: Exercise?
    func stateHeldExerciseIsFlagged() {}

    func viewInputDeclaredWithVarIsFalselyFlagged() {}
    var session: Session

    func viewInputDeclaredWithLetPasses() {}
    let week: Week

    func stateHeldAddressPasses() {}
    @State private var shownAddress: SessionAddress?

    var body: some View { EmptyView() }
}
