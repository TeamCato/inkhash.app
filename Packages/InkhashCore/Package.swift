// swift-tools-version: 6.0
import PackageDescription

// KennelKit comes from Kennel's repository (ADR 0073). KENNELKIT_DIR points at a local checkout named `kennel` instead,
// for working on both at once; relative to the repository root or absolute.
let kennelKit: Package.Dependency = {
    guard let local = Context.environment["KENNELKIT_DIR"], !local.isEmpty else {
        return .package(url: "https://github.com/teamcato/kennel", .upToNextMinor(from: "0.8.0"))
    }
    return .package(path: local.hasPrefix("/") ? local : Context.packageDirectory + "/../../" + local)
}()

let package = Package(
    name: "InkhashCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "InkhashCore", targets: ["InkhashCore"]),
    ],
    dependencies: [kennelKit],
    targets: [
        .target(
            name: "InkhashCore",
            dependencies: [.product(name: "KennelKit", package: "kennel")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "InkhashCoreTests",
            dependencies: ["InkhashCore", .product(name: "KennelKit", package: "kennel")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
