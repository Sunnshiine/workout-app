// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WorkoutTracker",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .executable(name: "workout", targets: ["WorkoutCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "WorkoutTracker",
            path: "WorkoutTracker",
            exclude: [
                "Views",
                "LiveActivity",
                "Assets.xcassets",
                "Fonts",
                "Sheets/GoogleAuth.swift",
                "WorkoutTrackerApp.swift",
                "Info.plist",
                "LaunchScreen.storyboard"
            ],
            // The offline Sheet (LocalWorkbook, WorkbookScenario, AppEnvironment.inMemory/directory) exists
            // for the CLI and tests. The Xcode app target never defines this, so the phone never ships it.
            swiftSettings: [.define("OFFLINE_SHEET")]
        ),
        .executableTarget(
            name: "WorkoutCLI",
            dependencies: [
                "WorkoutTracker",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "WorkoutCLI",
            exclude: ["README.md"]
        ),
        .testTarget(
            name: "WorkoutTrackerTests",
            dependencies: ["WorkoutTracker", "WorkoutCLI"],
            path: "Tests",
            exclude: ["UI", "Visual", "Unit/GoogleAuthTests.swift"]
        )
    ]
)
