// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dict",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "DictCore",
            path: "Sources/DictCore"
        ),
        .executableTarget(
            name: "Dict",
            dependencies: ["DictCore"],
            path: "Sources",
            exclude: ["DictCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
                .linkedFramework("CoreAudio"),
            ]
        ),
        .testTarget(
            name: "DictTests",
            dependencies: ["DictCore"],
            path: "Tests/DictTests"
        ),
    ]
)
