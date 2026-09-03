// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacProjector",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MacProjector",
            path: "Sources/MiPadProjector"
        )
    ]
)
