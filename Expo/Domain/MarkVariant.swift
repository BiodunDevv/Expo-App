import Foundation

/// The bot a person picked to represent Expo on this Mac.
enum MarkVariant: String, CaseIterable, Identifiable, Sendable {
    // Icons8 voxel robot, in five colors.
    case paper, blue, coral, green, violet
    // Libraries.dev bot avatars.
    case clover, flower, triangle, square, blob, ghost, circle, drop, star, droid, mech, alien, hexagon, cat, cloud, pill, pebble, puddle

    static let standard = MarkVariant.paper
    static let voxels: [MarkVariant] = [.paper, .blue, .coral, .green, .violet]
    static let avatars = allCases.filter { !$0.isVoxel }

    var id: Self { self }
    var isVoxel: Bool { Self.voxels.contains(self) }
    var title: String { rawValue.capitalized }

    /// Names of the bundled artwork, for the voxel robots only.
    var image: String { "Mark-\(rawValue)" }
    var menuImage: String { "Menu-\(rawValue)" }
    var animation: String { "robot-\(rawValue)" }
}
