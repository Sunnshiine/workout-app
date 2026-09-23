import SwiftUI

struct NoUppercaseMicrolabels {
    func textCaseUppercaseOutsideViewsPasses() -> some View {
        Text("Top set").textCase(.uppercase)
    }

    func uppercasedStringOutsideViewsPasses(label: String) -> String {
        label.uppercased()
    }
}
