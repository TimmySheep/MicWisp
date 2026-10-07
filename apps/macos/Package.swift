// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesktopClient",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "desktop-client", targets: ["DesktopClient"]),
    ],
    targets: [
        .executableTarget(
            name: "DesktopClient",
            path: "Sources/DesktopClient",
            resources: [.process("Resources")]
        ),
    ]
)
