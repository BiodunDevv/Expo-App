// swift-tools-version: 5.9
// Bot avatars and thinking orbs from Libraries.dev (MIT, see LICENSE), copied
// into the project and adapted for macOS. See README.md.
import PackageDescription

let package = Package(
    name: "LibrariesDev",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BotAvatarsKit", targets: ["BotAvatarsKit"]),
        .library(name: "ThinkingOrbsKit", targets: ["ThinkingOrbsKit"]),
    ],
    targets: [
        .target(name: "BotAvatarsKit"),
        .target(name: "ThinkingOrbsKit"),
    ]
)
