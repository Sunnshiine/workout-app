import SwiftUI

struct NoUppercaseMicrolabels {
    func textCaseUppercaseIsFlagged() -> some View {
        Text("Top set").textCase(.uppercase)
    }

    func uppercasedStringIsFlagged(label: String) -> some View {
        Text(label.uppercased())
    }

    func textCaseLowercasePasses() -> some View {
        Text("Top set").textCase(.lowercase)
    }
}
