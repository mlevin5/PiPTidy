// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScootPiP",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ScootPiPCore", targets: ["ScootPiPCore"]),
        .executable(name: "ScootPiP", targets: ["ScootPiP"])
    ],
    targets: [
        .target(name: "ScootPiPCore"),
        .executableTarget(name: "ScootPiP", dependencies: ["ScootPiPCore"]),
        .testTarget(name: "ScootPiPCoreTests", dependencies: ["ScootPiPCore"])
    ]
)

