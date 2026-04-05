// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "niri-mac",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "NiriMac",
            path: "Sources/NiriMac",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("IOKit"),
            ]
        ),
        .testTarget(
            name: "NiriMacTests",
            dependencies: [
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/NiriMacTests"
        ),
    ]
)
