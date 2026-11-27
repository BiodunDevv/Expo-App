import BotAvatarsKit
import SwiftUI

extension MarkVariant {
    var avatarType: BotAvatarType? { BotAvatarType(rawValue: rawValue) }

    /// An image for places that cannot show a view: the Dock and the menu bar.
    @MainActor func nsImage(points: CGFloat, tile: Bool) -> NSImage? {
        guard let type = avatarType else {
            return Bundle.main.image(forResource: tile ? "Icon-\(rawValue)" : menuImage)
        }
        let art = BotAvatarStill(type: type, size: points * (tile ? 0.62 : 0.96))
            .frame(width: points, height: points)
            .background {
                if tile {
                    RoundedRectangle(cornerRadius: points * 0.185)
                        .fill(Color(.sRGB, red: 0.949, green: 0.941, blue: 0.914))
                        .padding(points * 0.09)
                }
            }
        let renderer = ImageRenderer(content: art)
        renderer.scale = 2
        return renderer.nsImage
    }
}

/// The chosen bot, not moving: logos, lists and past messages.
struct MarkImage: View {
    var mark: MarkVariant
    var size: CGFloat

    var body: some View {
        Group {
            if let type = mark.avatarType {
                BotAvatarStill(type: type, size: size * 0.94)
            } else {
                Image(mark.image).resizable().interpolation(.high).scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .id(mark)
    }
}

/// The chosen bot, alive: floating controls and previews. It works while Expo is
/// answering, sleeps while Assist is paused, and holds still with Reduce Motion.
struct RobotMark: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var size: CGFloat
    /// Overrides the chosen bot, for previews.
    var variant: MarkVariant?

    var body: some View {
        let mark = variant ?? model.mark
        Group {
            if let type = mark.avatarType {
                // Drawn a little smaller so a hop stays inside small windows.
                BotAvatar(type: type, state: state, size: Double(size) * 0.82, paused: reduceMotion, interactive: false)
            } else {
                LoopingAnimation(name: mark.animation)
            }
        }
        .id(mark)
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var state: BotAvatarState {
        if variant != nil { return .default }
        if model.assist?.isAsking == true { return .working }
        return model.assist?.snapshot.lifecycle == .paused ? .sleeping : .default
    }
}

/// Every bot, with the selected one outlined.
struct MarkGrid: View {
    @Binding var selection: MarkVariant
    var size: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Bot avatars", MarkVariant.avatars)
            section("Voxel robots", MarkVariant.voxels)
        }
    }

    private func section(_ title: String, _ marks: [MarkVariant]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: size + 26), spacing: 8)], spacing: 8) {
                ForEach(marks) { cell($0) }
            }
        }
    }

    private func cell(_ mark: MarkVariant) -> some View {
        let chosen = mark == selection
        return Button { selection = mark } label: {
            VStack(spacing: 6) {
                MarkImage(mark: mark, size: size)
                Text(mark.title).font(.system(size: 11, weight: chosen ? .bold : .medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(chosen ? Theme.selected : Theme.surface, in: .rect(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(chosen ? Theme.accent : Theme.border, lineWidth: chosen ? 2 : 1) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mark.title)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// Shown once, before anything else, so the person starts with their own bot.
struct MarkPickerView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = MarkVariant.standard

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                RobotMark(size: 76, variant: selection)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose your Expo").font(.system(size: 20, weight: .bold))
                    Text("It appears on the floating button, in the app and in your Dock. Change it any time in Settings.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28).padding(.top, 34).padding(.bottom, 14)
            Hairline()
            ScrollView {
                MarkGrid(selection: $selection).padding(.horizontal, 28).padding(.vertical, 14)
            }
            Hairline()
            HStack {
                Spacer()
                Button("Use \(selection.title)") { model.chooseMark(selection) }
                    .buttonStyle(.expo)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28).padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { selection = model.mark }
    }
}
