import SwiftUI

struct LeadingAndSlantViaTheTypeRole {
    func handSetLineSpacingIsFlagged() -> some View {
        Text("Brace hard off the floor").lineSpacing(3)
    }

    func italicIsFlagged() -> some View {
        Text("Bench").italic()
    }

    func leadingFromTheTypeRolePasses() -> some View {
        Text("Brace hard off the floor").themeFont(.coachNote)
    }
}
