// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Screenshotter",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ScreenshotterCore", targets: ["ScreenshotterCore"]),
        .executable(name: "screenshotter-cli", targets: ["screenshotter-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift", from: "0.18.0"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift", from: "1.8.0"),
    ],
    targets: [
        .target(
            name: "ScreenshotterCore",
            dependencies: [
                .product(name: "P256K", package: "secp256k1.swift"),
                .product(name: "CryptoSwift", package: "CryptoSwift"),
            ]
        ),
        .executableTarget(
            name: "screenshotter-cli",
            dependencies: ["ScreenshotterCore"]
        ),
        .testTarget(
            name: "ScreenshotterCoreTests",
            dependencies: ["ScreenshotterCore"]
        ),
    ]
)
