// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "niri-mac",
    platforms: [.macOS(.v13)],
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
    ]
)
