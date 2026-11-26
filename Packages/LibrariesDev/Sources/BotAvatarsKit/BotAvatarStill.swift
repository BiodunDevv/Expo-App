import SwiftUI

/// Added for Expo: one resting frame with no clock, so it can be shown in long
/// lists and turned into an image with `ImageRenderer`.
public struct BotAvatarStill: View {
    private let type: BotAvatarType
    private let size: Double

    public init(type: BotAvatarType, size: Double) {
        self.type = type
        self.size = size
    }

    public var body: some View {
        // As `BotAvatar` does by default: the palette colour at saturation 1.5.
        var config = BotAvatarDrawConfig(type: type, color: type.paletteColor.shade(0, 0.25))
        config.still = true
        config.theme = .light
        let full = size * BOT_AVATAR_OVERSCAN
        return Color.clear
            .frame(width: size, height: size)
            .overlay {
                Canvas(opaque: false, colorMode: .nonLinear) { context, _ in
                    drawBotAvatarFrame(&context, box: size, pose: .rest(.default), cfg: config, state: BotAvatarRenderState())
                }
                .frame(width: full, height: full)
                .offset(y: -BOT_AVATAR_RISE * size)
                .allowsHitTesting(false)
            }
    }
}
