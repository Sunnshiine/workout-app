// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "crap",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CRAPKit", targets: ["CRAPKit"]),
        .executable(name: "crap", targets: ["crap"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "602.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "CRAPKit",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]
        ),
        .executableTarget(
            name: "crap",
            dependencies: [
                "CRAPKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "CRAPKitTests",
            dependencies: ["CRAPKit"]
        )
    ]
)
