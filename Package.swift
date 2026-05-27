// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WorkoutTracker",
    platforms: [.macOS(.v15), .iOS(.v18)],
    targets: [
        .target(
            name: "WorkoutTracker",
            path: "WorkoutTracker",
            exclude: [
                "Views",
                "Sheets/GoogleAuth.swift",
                "Sheets/GoogleSheetsClient.swift",
                "WorkoutTrackerApp.swift",
                "Info.plist",
                "LaunchScreen.storyboard",
            ]
        ),
        .testTarget(
            name: "WorkoutTrackerTests",
            dependencies: ["WorkoutTracker"],
            path: "WorkoutTrackerTests"
        ),
    ]
)
