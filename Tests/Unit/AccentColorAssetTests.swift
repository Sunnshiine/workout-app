import Foundation
import SwiftUI
import Testing

@testable import WorkoutTracker

private struct ColorSet: Decodable {
    let colors: [ColorSetEntry]
}

private struct ColorSetEntry: Decodable {
    struct Appearance: Decodable {
        let appearance: String
        let value: String
    }

    struct Swatch: Decodable {
        let components: [String: String]
    }

    let appearances: [Appearance]?
    let color: Swatch
}

private struct RGB: Equatable {
    let red: Int
    let green: Int
    let blue: Int
}

private func rgb(of swatch: ColorSetEntry.Swatch) throws -> RGB {
    func channel(_ name: String) throws -> Int {
        let hex = try #require(swatch.components[name]?.dropFirst(2), "\(name) is missing")
        return try #require(Int(hex, radix: 16), "\(name) is not 0x-prefixed hex")
    }
    return RGB(red: try channel("red"), green: try channel("green"), blue: try channel("blue"))
}

@MainActor
private func rgb(of color: Color) -> RGB {
    let resolved = color.resolve(in: EnvironmentValues())
    return RGB(
        red: Int((resolved.red * 255).rounded()),
        green: Int((resolved.green * 255).rounded()),
        blue: Int((resolved.blue * 255).rounded())
    )
}

@MainActor
@Test func theAccentColorAssetMatchesTheThemesActionGreens() throws {
    let url = try RepositoryFiles.existingURL(of: "App/Assets.xcassets/AccentColor.colorset/Contents.json")
    let colorSet = try JSONDecoder().decode(ColorSet.self, from: Data(contentsOf: url))
    let universal = try #require(colorSet.colors.first { $0.appearances == nil })
    let dark = try #require(
        colorSet.colors.first { $0.appearances?.contains { $0.appearance == "luminosity" && $0.value == "dark" } == true }
    )

    #expect(try rgb(of: universal.color) == rgb(of: Theme.Paint.actionDay))
    #expect(try rgb(of: dark.color) == rgb(of: Theme.Paint.actionNight))
}
