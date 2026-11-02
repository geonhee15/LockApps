// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LockApps",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LockApps",
            path: "Sources/LockApps"
        )
    ]
)
