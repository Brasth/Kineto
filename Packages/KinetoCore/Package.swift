// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "KinetoCore",
    platforms: [.macOS("26.1")],
    products: [
        .library(name: "KinetoCore", targets: ["KinetoCore"])
    ],
    targets: [
        .binaryTarget(
            name: "CWhisper",
            path: "../../Binaries/CWhisper.xcframework"
        ),
        .target(
            name: "KinetoCore",
            dependencies: ["CWhisper"],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Foundation"),
                .linkedFramework("Metal"),
                .linkedFramework("Speech"),
                .linkedLibrary("c++")
            ]
        ),
        .testTarget(name: "KinetoCoreTests", dependencies: ["KinetoCore"])
    ],
    swiftLanguageModes: [.v6]
)
