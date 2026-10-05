// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InkhashCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "InkhashCore", targets: ["InkhashCore"]),
    ],
    targets: [
        .target(
            name: "InkhashCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "InkhashCoreTests",
            dependencies: ["InkhashCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
