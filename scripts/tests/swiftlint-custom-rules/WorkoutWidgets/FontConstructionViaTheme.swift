import SwiftUI

enum FontConstructionViaTheme {
    static func shorthandTextStyleInTheWidgetPasses() -> Text {
        Text("Squat").font(.caption.weight(.bold))
    }
}
