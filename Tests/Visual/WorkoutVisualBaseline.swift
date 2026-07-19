import Foundation
import SnapshotTesting
import SwiftUI
import UIKit

@testable import WorkoutTracker

/// Shared constants and the pinned device geometry for every Greenhouse Visual Baseline (ADR-0007).
enum WorkoutVisualBaseline {
    static let localeIdentifier = "en_US"
    static let dynamicTypeSize: DynamicTypeSize = .large
    static let precision: Float = 1.0
    static let labelAntialiasingPrecision: Float = 0.999
}

extension ViewImageConfig {
    /// The pinned iPhone 17 Pro geometry for a Greenhouse baseline. The interface-style trait follows
    /// the appearance so Night renders inside a dark system context — the Visual layer's equivalent of
    /// the `-WORKOUT_THEME day|night` screenshot pin (PRD #458 slice 8).
    @MainActor
    static func workoutVisualBaseline(_ appearance: Theme.Appearance = .day) -> ViewImageConfig {
        let style: UIUserInterfaceStyle =
            Theme.palette(for: appearance).preferredColorScheme == .dark ? .dark : .light
        return ViewImageConfig(
            safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0),
            size: CGSize(width: 402, height: 874),
            traits: UITraitCollection { traits in
                traits.displayScale = 3
                traits.userInterfaceStyle = style
                traits.preferredContentSizeCategory = .large
                traits.layoutDirection = .leftToRight
            }
        )
    }
}

// MARK: - Wholesale Day/Night capture

/// Captures a redesigned screen in **both** shipping appearances — the Visual layer's equivalent of
/// the `-WORKOUT_THEME day|night` screenshot pin (PRD #458 slice 8, ADR-0007). Each appearance lands
/// its own committed Visual Baseline (`…-day`, `…-night`), so the deterministic gate covers the
/// Greenhouse room and its Night re-light (DESIGN.md §2, the Room Re-lights Rule).
///
/// `hosted` wraps a component on living paper with the standard host padding; a full-screen view
/// (one that already fills the device) passes `hosted: false` and only receives the appearance
/// environment. The `content` closure is handed the appearance so a test can paint an appearance-
/// matched backdrop when it composes its own frame.
@MainActor
func assertGreenhouseBaselines<Content: View>(
    hosted: Bool = true,
    precision: Float = WorkoutVisualBaseline.precision,
    perceptualPrecision: Float = 1,
    fileID: StaticString = #fileID,
    file filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column,
    @ViewBuilder content: (Theme.Appearance) -> Content
) {
    for appearance in Theme.Appearance.allCases {
        let palette = Theme.palette(for: appearance)
        let inner = content(appearance)
        let view: AnyView = hosted
            ? AnyView(VisualBaselineHost(appearance: appearance) { inner })
            : AnyView(
                inner
                    .environment(\.themePalette, palette)
                    .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
                    .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)
                    .preferredColorScheme(palette.preferredColorScheme)
            )

        assertSnapshot(
            of: view,
            as: .image(
                precision: precision,
                perceptualPrecision: perceptualPrecision,
                layout: .device(config: .workoutVisualBaseline(appearance))
            ),
            fileID: fileID,
            file: filePath,
            testName: "\(testName)-\(appearance.rawValue)",
            line: line,
            column: column
        )
    }
}

/// Hosts a component on the appearance's living paper with the standard baseline padding and
/// environment (DESIGN.md §2). Re-light is honest: the paper, palette, and color scheme all follow
/// the appearance, so a Day and a Night capture differ only by the room's light.
struct VisualBaselineHost<Content: View>: View {
    let appearance: Theme.Appearance
    @ViewBuilder let content: Content

    var body: some View {
        let palette = Theme.palette(for: appearance)
        ZStack {
            palette.paperBackground
                .ignoresSafeArea()

            content
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.themePalette, palette)
        .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
        .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)
        .preferredColorScheme(palette.preferredColorScheme)
    }
}

// MARK: - Shared fixtures

/// Retains configured scenarios for the lifetime of a Visual test run so their backing stores are
/// not deallocated mid-render.
@MainActor
enum VisualBaselineFixtureRetainer {
    private static var retainedScenarios: [ConfiguredAppScenario] = []

    static func retain(_ scenario: ConfiguredAppScenario) {
        retainedScenarios.append(scenario)
    }
}

/// A no-op Sheets client so Visual tests never touch the network while a real store is on screen.
actor VisualBaselineNoopSheetsClient: SheetsClient {
    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        []
    }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        SheetSnapshot(values: [], rowVisibility: [:])
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}
}
