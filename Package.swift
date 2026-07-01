// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Pinger",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Pinger",
            path: "Sources/Pinger"
        )
    ]
)
