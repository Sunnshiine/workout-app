@MainActor
final class ModelHeldAcrossReload {
    func fakeHoldingASessionInTestsPasses() {}
    var session: Session?
}
