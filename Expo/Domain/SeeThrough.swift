/// How much of the meeting shows through the floating windows. Text always sits
/// on a card dark enough to read over a white or a black screen.
enum SeeThrough: String, Codable, CaseIterable, Identifiable, Sendable {
    case clear, tinted, solid
    var id: Self { self }

    var title: String {
        switch self {
        case .clear: "Clear"
        case .tinted: "Tinted"
        case .solid: "Solid"
        }
    }

    /// Opacity of the cards that hold text.
    var card: Double {
        switch self {
        case .clear: 0.75
        case .tinted: 0.89
        case .solid: 1
        }
    }
}
