// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HeadsUpCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "HeadsUpCore", targets: ["HeadsUpCore"])],
    targets: [
        .target(
            name: "HeadsUpCore",
            path: "HeadsUp/Core"
        ),
        .testTarget(
            name: "HeadsUpCoreTests",
            dependencies: ["HeadsUpCore"],
            path: "HeadsUpTests"
        )
    ]
)

