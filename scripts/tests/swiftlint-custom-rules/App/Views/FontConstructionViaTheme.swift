import SwiftUI

struct FontConstructionViaTheme {
    func fontCustomIsFlagged() -> some View {
        Text("Squat").font(Font.custom("Fraunces", size: 17))
    }

    func systemSizeIsFlagged() -> some View {
        Text("Squat").font(.system(size: 17, weight: .semibold))
    }

    func everyShorthandStyleIsFlagged() -> some View {
        VStack {
            Text("Squat").font(.largeTitle)
            Text("Squat").font(.title)
            Text("Squat").font(.title2)
            Text("Squat").font(.title3)
            Text("Squat").font(.headline)
            Text("Squat").font(.subheadline)
            Text("Squat").font(.body)
            Text("Squat").font(.callout)
            Text("Squat").font(.footnote)
            Text("Squat").font(.caption)
            Text("Squat").font(.caption2)
        }
    }

    func whitespaceInsideTheParenIsFlagged() -> some View {
        Text("Squat").font( .body)
    }

    func themeFontPasses() -> some View {
        Text("Squat").font(Theme.font(.exerciseName))
    }

    func shorthandWordBoundaryNearMissPasses() -> some View {
        Text("Squat").font(.titleBar)
    }
}
