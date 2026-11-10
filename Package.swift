// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DeckPilot",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StreamDockKit", targets: ["StreamDockKit"]),
        .executable(name: "DeckPilot", targets: ["DeckPilot"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.9.0"),
    ],
    targets: [
        .target(name: "StreamDockKit"),
        .target(name: "DeckCore"),
        .executableTarget(
            name: "DeckPilot",
            dependencies: ["StreamDockKit", "DeckCore", .product(name: "Sparkle", package: "Sparkle")]
        ),
        .testTarget(name: "StreamDockKitTests", dependencies: ["StreamDockKit"]),
        .testTarget(name: "DeckCoreTests", dependencies: ["DeckCore"]),
    ]
)
