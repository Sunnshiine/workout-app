import SwiftUI

enum NoUppercaseMicrolabels {
    static func uppercaseLabelInTheWidgetPasses() -> some View {
        Text("Rest").textCase(.uppercase)
    }
}
