// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Sisyphus",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Sisyphus", targets: ["Sisyphus"])],
    targets: [
        .target(name: "ClimbCore"),
        .executableTarget(name: "Sisyphus", dependencies: ["ClimbCore"]),
        .executableTarget(name: "ClimbChecks", dependencies: ["ClimbCore"], path: "Tests/ClimbChecks")
    ]
)
