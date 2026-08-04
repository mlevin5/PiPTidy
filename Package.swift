// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PiPTidy",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PiPTidyCore", targets: ["PiPTidyCore"]),
        .executable(name: "PiPTidy", targets: ["PiPTidy"])
    ],
    targets: [
        .target(name: "PiPTidyCore"),
        .executableTarget(name: "PiPTidy", dependencies: ["PiPTidyCore"]),
        .testTarget(name: "PiPTidyCoreTests", dependencies: ["PiPTidyCore"])
    ]
)
