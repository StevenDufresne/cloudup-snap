// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Screenshotter",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ScreenshotterCore", targets: ["ScreenshotterCore"]),
        .executable(name: "screenshotter-cli", targets: ["screenshotter-cli"]),
        .executable(name: "Screenshotter", targets: ["Screenshotter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift", from: "0.18.0"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift", from: "1.8.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
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
        .testTarget(
            name: "KeychainStoreTests",
            dependencies: ["ScreenshotterCore"]
        ),
        .executableTarget(
            name: "Screenshotter",
            dependencies: ["ScreenshotterCore"],
            resources: [.copy("App/Info.plist.template")]
        ),
        .testTarget(
            name: "ScreenshotterTests",
            dependencies: [
                "Screenshotter",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ]
        ),
    ]
)
