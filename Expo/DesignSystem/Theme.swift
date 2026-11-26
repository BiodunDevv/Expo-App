import SwiftUI

/// Paper and ink: warm off-white and charcoal, with near-black or off-white
/// emphasis. Color is kept for status marks.
enum Theme {
    static let background = Color(light: 0xFAF9F5, dark: 0x262624)
    static let sidebar = Color(light: 0xF2F0E9, dark: 0x1F1E1D)
    static let surface = Color(light: 0xFFFFFF, dark: 0x30302E)
    static let subtle = Color(light: 0xF4F2EC, dark: 0x3A3A37)
    static let selected = Color(light: 0xE8E5DB, dark: 0x3A3A37)
    static let border = Color(light: 0xE8E6DF, dark: 0x42423E)
    static let text = Color(light: 0x1F1E1D, dark: 0xF5F4EF)
    static let secondary = Color(light: 0x57554F, dark: 0xBAB8B0)
    static let tertiary = Color(light: 0x6B6963, dark: 0xA8A69E)
    /// The one emphasis color.
    static let accent = Color(light: 0x1F1E1D, dark: 0xF5F4EF)
    static let accentSoft = Color(light: 0xEFEDE5, dark: 0x42423E)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x1F1E1D)
    static let danger = Color(light: 0xB53A32, dark: 0xFF8A7E)
    static let dangerSoft = Color(light: 0xFAE7E4, dark: 0x48302C)
    static let success = Color(light: 0x2A7040, dark: 0x7BD394)
    static let successSoft = Color(light: 0xE5F1E4, dark: 0x2D4030)
    static let warning = Color(light: 0x855600, dark: 0xF0B456)
    static let warningSoft = Color(light: 0xF8EED7, dark: 0x453922)
}

extension Color {
    init(light: UInt32, dark: UInt32, lightOpacity: Double = 1, darkOpacity: Double = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                           blue: Double(hex & 0xFF) / 255, alpha: isDark ? darkOpacity : lightOpacity)
        })
    }
}
