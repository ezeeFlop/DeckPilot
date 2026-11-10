// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DeckPilot",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StreamDockKit", targets: ["StreamDockKit"]),
        .executable(name: "DeckPilot", targets: ["DeckPilot"]),
    ],
    targets: [
        .target(name: "StreamDockKit"),
        .target(name: "DeckCore"),
        .executableTarget(name: "DeckPilot", dependencies: ["StreamDockKit", "DeckCore"]),
        .testTarget(name: "StreamDockKitTests", dependencies: ["StreamDockKit"]),
        .testTarget(name: "DeckCoreTests", dependencies: ["DeckCore"]),
    ]
)
