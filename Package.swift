// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DeskBro",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "DeskBro", path: "Sources/DeskBro")
    ]
)
