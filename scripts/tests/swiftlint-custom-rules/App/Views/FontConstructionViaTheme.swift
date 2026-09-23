import SwiftUI

struct FontConstructionViaTheme {
    func fontCustomIsFlagged() -> some View {
        Text("Squat").font(Font.custom("Fraunces", size: 17))
    }

    func systemSizeIsFlagged() -> some View {
        Text("Squat").font(.system(size: 17, weight: .semibold))
    }

    func headlineShorthandIsFlagged() -> some View {
        Text("Squat").font(.headline)
    }

    func title2ShorthandIsFlagged() -> some View {
        Text("Squat").font(.title2)
    }

    func themeFontPasses() -> some View {
        Text("Squat").font(Theme.font(.exerciseName))
    }

    func shorthandWordBoundaryNearMissPasses() -> some View {
        Text("Squat").font(.titleBar)
    }
}
