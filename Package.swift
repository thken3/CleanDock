// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CleanDock",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CleanDockCore"),
        .executableTarget(name: "CleanDock", dependencies: ["CleanDockCore"]),
        .testTarget(name: "CleanDockCoreTests", dependencies: ["CleanDockCore"]),
    ],
    swiftLanguageModes: [.v5]
)
