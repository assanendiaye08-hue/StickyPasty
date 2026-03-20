// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StickyPasty",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "StickyPasty",
            path: "Sources/StickyPasty",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ApplicationServices"),
            ]
        )
    ]
)
