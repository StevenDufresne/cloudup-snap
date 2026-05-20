// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CloudupSnap",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CloudupSnapCore", targets: ["CloudupSnapCore"]),
        .executable(name: "cloudupsnap-cli", targets: ["cloudupsnap-cli"]),
        .executable(name: "CloudupSnap", targets: ["CloudupSnap"]),
    ],
    dependencies: [
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift", from: "0.18.0"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift", from: "1.8.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    ],
    targets: [
        .target(
            name: "CloudupSnapCore",
            dependencies: [
                .product(name: "P256K", package: "secp256k1.swift"),
                .product(name: "CryptoSwift", package: "CryptoSwift"),
            ]
        ),
        .executableTarget(
            name: "cloudupsnap-cli",
            dependencies: ["CloudupSnapCore"]
        ),
        .testTarget(
            name: "CloudupSnapCoreTests",
            dependencies: ["CloudupSnapCore"]
        ),
        .testTarget(
            name: "KeychainStoreTests",
            dependencies: ["CloudupSnapCore"]
        ),
        .executableTarget(
            name: "CloudupSnap",
            dependencies: ["CloudupSnapCore"],
            resources: [.copy("App/Info.plist.template")]
        ),
        .testTarget(
            name: "CloudupSnapTests",
            dependencies: [
                "CloudupSnap",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ]
        ),
    ]
)
