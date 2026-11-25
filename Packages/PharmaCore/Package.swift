// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PharmaCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "PharmaCore", targets: ["PharmaCore"])
    ],
    targets: [
        .target(name: "PharmaCore"),
        .testTarget(name: "PharmaCoreTests", dependencies: ["PharmaCore"])
    ]
)
