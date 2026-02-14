// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dict",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Dict",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
            ]
        )
    ]
)
