import Foundation
import SnapshotTesting
import SwiftUI
import Testing
import UIKit

@testable import WorkoutTracker

/// Settings leaves `GlassBearingViewsVisualTests` because it no longer bears glass; this suite is its
/// replacement coverage, and it adds the Night appearance the glass suite never rendered.
@MainActor
@Suite(.snapshots(record: .never))
struct SettingsViewVisualTests {
    @Test func settingsViewMatchesVisualBaseline() throws {
        try assertSettings(appearance: .day, colorScheme: .light, config: .workoutVisualBaseline)
    }

    @Test func settingsViewMatchesNightVisualBaseline() throws {
        try assertSettings(appearance: .night, colorScheme: .dark, config: .workoutVisualBaselineNight)
    }

    @Test(arguments: [(Theme.Appearance.day, ColorScheme.light), (.night, .dark)])
    func actionRowsDrawSystemColorsUnderTheAppTint(appearance: Theme.Appearance, colorScheme: ColorScheme) throws {
        let appTint = try #require(UIColor(named: "AccentColor"), "the test host carries the app's AccentColor")
        let settings = try settingsView(appearance: appearance)
            .tint(Color(uiColor: appTint))
            .preferredColorScheme(colorScheme)
        let trait = UITraitCollection(userInterfaceStyle: UIUserInterfaceStyle(colorScheme))
        let actionRows: [(id: String, system: UIColor)] = [
            ("settings-training-sheet-row", .systemBlue),
            ("settings-sync-now-button", .systemBlue),
            ("settings-sign-out-button", .systemRed)
        ]
        let counts = try AccessibilityHost.read(settings, in: [CGSize(width: 402, height: 874)]) { window in
            try actionRows.map { id, system in
                let row = try #require(window.accessibilityFrames { $0.elementIdentifier == id }.first, "\(id) is on screen")
                return (
                    system: try pixels(near: system.resolvedColor(with: trait), in: window, within: row),
                    tint: try pixels(near: appTint.resolvedColor(with: trait), in: window, within: row)
                )
            }
        }[0]
        for (row, count) in zip(actionRows, counts) {
            #expect(count.system > 200, "\(row.id) draws its system colour in \(count.system) pixels")
            #expect(count.tint == 0, "\(row.id) draws the app tint in \(count.tint) pixels")
        }
    }

    private func assertSettings(
        appearance: Theme.Appearance,
        colorScheme: ColorScheme,
        config: ViewImageConfig,
        testName: String = #function
    ) throws {
        assertSnapshot(
            of: try settingsView(appearance: appearance).preferredColorScheme(colorScheme),
            as: .image(
                precision: WorkoutVisualBaseline.precision,
                perceptualPrecision: 1,
                layout: .device(config: config)
            ),
            testName: testName
        )
    }

    private func settingsView(appearance: Theme.Appearance) throws -> some View {
        let scenario = try WorkoutScenarios.freshConfiguredApp()
        VisualFixtureRetainer.retain(scenario)
        let sync = SyncCoordinator(client: VisualNoopSheetsClient(), context: scenario.context)

        return SettingsView()
            .environment(scenario.settings)
            .environment(sync)
            .environment(SheetConnection(settings: scenario.settings, sync: sync) { scenario.store.reload() })
            .environment(scenario.store)
            .environment(\.themePalette, Theme.palette(for: appearance))
            .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
            .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)
    }

    private func pixels(near color: UIColor, in window: UIWindow, within region: CGRect) throws -> Int {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        try #require(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        let target = [red, green, blue].map { Int(($0 * 255).rounded()) }
        let channelTolerance = 8

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: region, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let cgImage = try #require(image.cgImage)
        let sRGB = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var pixels = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        return try pixels.withUnsafeMutableBytes { bytes in
            let context = try #require(
                CGContext(
                    data: bytes.baseAddress,
                    width: cgImage.width,
                    height: cgImage.height,
                    bitsPerComponent: 8,
                    bytesPerRow: cgImage.width * 4,
                    space: sRGB,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            )
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            return stride(from: 0, to: bytes.count, by: 4).filter { offset in
                (0..<3).allSatisfy { abs(Int(bytes[offset + $0]) - target[$0]) <= channelTolerance }
            }
            .count
        }
    }
}
