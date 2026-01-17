// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sten",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.9")
    ],
    targets: [
        .executableTarget(
            name: "Sten",
            dependencies: ["FluidAudio"],
            path: "app/Sten",
            exclude: ["Info.plist", "Sten.entitlements"]
        )
    ]
)
