import SwiftUI
import UIKit

struct SystemInkOutsideThePalette {
    func secondaryShapeStyleIsFlagged() -> some View {
        Text("Squat").foregroundStyle(.secondary)
    }

    func tertiaryShapeStyleIsFlagged() -> some View {
        Text("Squat").foregroundStyle(.tertiary)
    }

    func quaternaryShapeStyleIsFlagged() -> some View {
        Text("Squat").foregroundStyle(.quaternary)
    }

    func secondaryAsTheSecondOfTwoStylesIsFlagged() -> some View {
        Label("Squat", systemImage: "scalemass").foregroundStyle(.primary, .secondary)
    }

    func colorSecondaryInAFillIsFlagged() -> some View {
        Circle().fill(Color.secondary.opacity(0.4))
    }

    func hierarchicalShapeStyleTertiaryIsFlagged() -> some View {
        Text("Squat").foregroundStyle(HierarchicalShapeStyle.tertiary)
    }

    func uiKitTertiaryLabelIsFlagged() -> some View {
        Text("Squat").foregroundStyle(Color(.tertiaryLabel))
    }

    func uiColorSecondaryLabelIsFlagged() -> UIColor {
        UIColor.secondaryLabel
    }

    func enumCaseNamedSecondaryIsFalselyFlagged(rank: LiftRank) -> Bool {
        rank == .secondary
    }

    func paletteTextSecondaryPasses(palette: ThemePalette) -> some View {
        Text("Squat").foregroundStyle(palette.textSecondary)
    }

    func propertyNamedSecondaryTextPasses(colors: LiveActivityColors) -> some View {
        Text("Squat").foregroundStyle(colors.secondaryText)
    }

    func secondarySystemBackgroundGroundPasses() -> some View {
        Text("Squat").background(Color(.secondarySystemBackground))
    }

    func secondaryActionPlacementPasses() -> some View {
        Text("Squat").toolbar { ToolbarItem(placement: .secondaryAction) { Text("Edit") } }
    }

    func wordsInACommentPasses() -> some View {
        // Not .foregroundStyle(.secondary) or Color(.tertiaryLabel).
        Text("Squat")
    }

    func wordsInAStringPasses() -> some View {
        Text(".foregroundStyle(.secondary) and Color(.tertiaryLabel)")
    }

    func hierarchicalVariantOfAColorIsMissed() -> some View {
        Text("Squat").foregroundStyle(Color.blue.secondary)
    }

    func quinaryShapeStyleIsFlagged() -> some View {
        Text("Squat").foregroundStyle(.quinary)
    }

    func shapeStyleSecondaryIsFlagged() -> some View {
        Text("Squat").foregroundStyle(ShapeStyle.secondary)
    }
}
