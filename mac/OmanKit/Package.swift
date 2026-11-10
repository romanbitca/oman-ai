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
        // GRDB 7.12.0, pinned to its commit so a release never picks up code nobody chose.
        .package(url: "https://github.com/groue/GRDB.swift.git", revision: "92a554cd0d5e8d67cb18993c6054e73fe42c066c"),
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
