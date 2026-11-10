// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OmanKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OmanCore", targets: ["OmanCore"]),
        .library(name: "ClaudeAPI", targets: ["ClaudeAPI"]),
        .library(name: "OmanStorage", targets: ["OmanStorage"]),
        .library(name: "SystemBridge", targets: ["SystemBridge"]),
        .library(name: "OmanUI", targets: ["OmanUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.12.0"),
    ],
    targets: [
        .target(name: "OmanCore"),
        .target(name: "ClaudeAPI", dependencies: ["OmanCore"]),
        .target(
            name: "OmanStorage",
            dependencies: ["OmanCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(name: "SystemBridge", dependencies: ["OmanCore"]),
        .target(name: "OmanUI", dependencies: ["OmanCore"]),
        .testTarget(name: "ClaudeAPITests", dependencies: ["ClaudeAPI"]),
        .testTarget(name: "OmanStorageTests", dependencies: ["OmanStorage"]),
        .testTarget(name: "SystemBridgeTests", dependencies: ["SystemBridge"]),
        .testTarget(name: "OmanUITests", dependencies: ["OmanUI"]),
    ]
)
