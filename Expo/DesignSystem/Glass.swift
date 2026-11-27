import SwiftUI

/// The dark glass of the floating windows. They are always drawn in the dark
/// appearance, so light text reads whatever is behind them.
enum Glass {
    static let base = Color(.sRGB, red: 0.07, green: 0.075, blue: 0.09)
    static let fill = Color.white.opacity(0.08)
    /// Where text is typed.
    static let field = Color.black.opacity(0.42)
    static let selected = Color.white.opacity(0.17)
    static let line = Color.white.opacity(0.16)
}

extension View {
    /// A card of glass that text can sit on.
    /// `denser` adds opacity where text is typed and has to read at once.
    func glassCard(radius: CGFloat = 22, denser: Double = 0) -> some View { modifier(GlassCard(radius: radius, denser: denser)) }

    /// A dark edge around text, so it holds against whatever shows through.
    func textHalo() -> some View { modifier(TextHalo()) }
}

extension EnvironmentValues {
    /// True inside a card that something can be seen through.
    @Entry var onGlass = false
}

private struct TextHalo: ViewModifier {
    @Environment(\.onGlass) private var onGlass

    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(onGlass ? 0.95 : 0), radius: onGlass ? 1.2 : 0, y: onGlass ? 0.5 : 0)
    }
}

private struct GlassCard: ViewModifier {
    @Environment(AppModel.self) private var model
    var radius: CGFloat
    var denser: Double

    func body(content: Content) -> some View {
        content
            .environment(\.onGlass, model.state.settings.seeThrough != .solid)
            .background(Glass.base.opacity(min(0.98, model.state.settings.seeThrough.card + denser)), in: .rect(cornerRadius: radius))
            .clipShape(.rect(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).stroke(Glass.line) }
    }
}
