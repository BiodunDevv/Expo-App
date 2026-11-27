// swift-tools-version: 5.9
// Kits from Libraries.dev (MIT, see LICENSE), copied into the project. See
// README.md. Build through Xcode: it compiles the `.metal` shaders.
import PackageDescription

let package = Package(
    name: "LibrariesDev",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BotAvatarsKit", targets: ["BotAvatarsKit"]),
        .library(name: "ThinkingOrbsKit", targets: ["ThinkingOrbsKit"]),
        .library(name: "BorderBeamKit", targets: ["BorderBeamKit"]),
        .library(name: "VoiceRingKit", targets: ["VoiceRingKit"]),
    ],
    targets: [
        .target(name: "BotAvatarsKit"),
        .target(name: "ThinkingOrbsKit"),
        .target(name: "BorderBeamKit", resources: [.copy("Resources/beam-spec.json"), .process("BeamShaders.metal")]),
        .target(name: "VoiceCore", resources: [.process("Render/Refract.metal")]),
        .target(name: "VoiceRingKit", dependencies: ["VoiceCore"]),
    ]
)
