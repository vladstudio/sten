// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sten",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.9"),
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
