/// The Sheet-connect screen's copy (DESIGN.md §5.8, picks sunbird-moments-c/-e).
/// The flat-calm composition speaks quietly: a Fraunces title that names the act
/// of planting the program, a two-line subtitle, and a single green
/// **Connect Google Sheet** capsule replacing the stock white Google rectangle.
struct OnboardingConnectPresentation: Equatable, Sendable {
    let title: String
    let subtitle: String
    let connectButtonTitle: String

    init() {
        title = "Plant the program."
        subtitle = "Connect the Sheet your coach programs. The app keeps it fresh and carries your logs back."
        connectButtonTitle = "Connect Google Sheet"
    }
}
