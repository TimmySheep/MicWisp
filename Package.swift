// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MicYouCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "MicYouCore", targets: ["MicYouCore"])
    ],
    targets: [
        .target(name: "MicYouCore"),
        .testTarget(name: "MicYouCoreTests", dependencies: ["MicYouCore"])
    ]
)
