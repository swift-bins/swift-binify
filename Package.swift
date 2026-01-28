// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "swift-binify",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "swift-binify", targets: ["swift-binify"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/maxchuquimia/cockle", branch: "master"),
        .package(url: "https://github.com/giginet/Scipio.git", from: "0.21.0"),
    ],
    targets: [
        .executableTarget(
            name: "swift-binify",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Cockle", package: "cockle"),
                .product(name: "ScipioKit", package: "Scipio"),
            ]
        )
    ]
)
