// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EchoSim",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "EchoSim", targets: ["EchoSim"]),
    ],
    targets: [
        .target(name: "EchoSim"),
        .testTarget(name: "EchoSimTests", dependencies: ["EchoSim"]),
    ]
)
