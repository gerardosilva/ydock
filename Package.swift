// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "yDock",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "yDock", path: "Sources/yDock")
    ]
)
