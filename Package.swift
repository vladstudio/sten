// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Sten",
    platforms: [.macOS(.v15)],
    dependencies: [
        // traits: [] opts out of FluidAudio's bundled NeMo text-normalization
        // engine (10MB static Rust lib) — unused by this app. Requires 6.2.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.7", traits: []),
        .package(path: "../app-kit"),
    ],
    targets: [
        .executableTarget(
            name: "Sten",
            dependencies: [
                "FluidAudio",
                .product(name: "MacAppKit", package: "app-kit"),
            ],
            path: "app/Sten",
            exclude: ["Info.plist", "Sten.entitlements"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
