// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Hibou",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Hibou",
            path: "Sources/Hibou"
        )
    ]
)
