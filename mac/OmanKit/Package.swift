// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OmanKit",
    platforms: [.macOS(.v14), .iOS(.v26)],
    products: [
        .library(name: "OmanCore", targets: ["OmanCore"]),
        .library(name: "ClaudeAPI", targets: ["ClaudeAPI"]),
        .library(name: "OmanStorage", targets: ["OmanStorage"]),
        .library(name: "SystemBridge", targets: ["SystemBridge"]),
        .library(name: "OmanUI", targets: ["OmanUI"]),
        .library(name: "OmanSpeech", targets: ["OmanSpeech"]),
        .library(name: "OmanSync", targets: ["OmanSync"]),
    ],
    dependencies: [
        // GRDB 7.12.0, pinned to its commit so a release never picks up code nobody chose.
        .package(url: "https://github.com/groue/GRDB.swift.git", revision: "92a554cd0d5e8d67cb18993c6054e73fe42c066c"),
        // FluidAudio 0.18.3, which runs Parakeet for dictation. With no traits, only its speech recognition is
        // built: none of its voices, speaker separation or prebuilt text normaliser.
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            revision: "c8b41f98eae668794dd0083bbe028fe7e6585051",
            traits: []
        ),
        // WhisperKit 1.1.1, from Argmax's argmax-oss-swift, which runs Whisper for dictation.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", revision: "1bbc57cb7fe6410248a685b1c5a3c6d56adc2ed4"),
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
        .target(
            name: "OmanSpeech",
            dependencies: [
                "OmanCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ]
        ),
        .target(name: "OmanSync", dependencies: ["OmanCore"]),
        .testTarget(name: "ClaudeAPITests", dependencies: ["ClaudeAPI"]),
        .testTarget(name: "OmanStorageTests", dependencies: ["OmanStorage"]),
        .testTarget(name: "SystemBridgeTests", dependencies: ["SystemBridge"]),
        .testTarget(name: "OmanUITests", dependencies: ["OmanUI"]),
        .testTarget(name: "OmanSpeechTests", dependencies: ["OmanSpeech"]),
        .testTarget(name: "OmanSyncTests", dependencies: ["OmanSync"]),
    ]
)
