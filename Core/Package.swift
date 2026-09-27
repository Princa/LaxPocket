// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LaxPocketCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LaxPocketCore", targets: ["LaxPocketCore"])
    ],
    targets: [
        .target(name: "LaxPocketCore"),
        .testTarget(name: "LaxPocketCoreTests", dependencies: ["LaxPocketCore"])
    ]
)
