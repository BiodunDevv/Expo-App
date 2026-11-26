import SwiftUI

/// Whether Expo appears in screen shares, shown the same way everywhere. The
/// switch is on while Expo is hidden, and the words always state the current state.
struct PrivacyToggle: View {
    var body: some View { PrivacySwitchButton(style: .chip) }
}

/// The card form used on the sign-in screen and in the sidebar.
struct PrivacyRow: View {
    /// Shorter wording for narrow places.
    var compact = false
    var body: some View { PrivacySwitchButton(style: .row, compact: compact) }
}

private struct PrivacySwitchButton: View {
    enum Style { case chip, row }
    var style: Style
    var compact = false

    @Environment(AppModel.self) private var model
    @State private var explaining = false
    @State private var hovering = false

    private var privacy: CapturePrivacy { model.capturePrivacy }

    private var headline: String {
        if compact { return privacy.title }
        return privacy.isHidden ? "Hidden from screen shares" : "Visible in screen shares"
    }

    private var caption: String {
        switch privacy {
        case .hidden: compact ? "Only you see Expo" : "Only you can see Expo"
        case .visible: compact ? "Others can see it" : "People on your call can see Expo"
        case .unavailable: compact ? "Not available" : "Hiding is not available on this account"
        }
    }

    /// A 3D shield while hidden and a 3D eye while visible.
    private func art(_ size: CGFloat) -> some View {
        ZStack {
            Image(privacy.isHidden ? "privacy-hidden" : "privacy-visible")
                .resizable().interpolation(.high).scaledToFit()
                .id(privacy.isHidden)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
        .frame(width: size, height: size)
    }

    var body: some View {
        Button {
            if privacy == .unavailable { explaining = true }
            else { model.setHiddenFromCapture(!privacy.isHidden) }
        } label: {
            Group {
                switch style {
                case .chip: chip
                case .row: row
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.22), value: privacy)
        .help(privacy == .unavailable ? privacy.detail : "\(privacy.detail). Click to \(privacy.isHidden ? "show" : "hide").")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hide from screen sharing")
        .accessibilityValue(privacy.detail)
        .accessibilityAddTraits(.isToggle)
        .popover(isPresented: $explaining) { explanation }
    }

    private var chip: some View {
        HStack(spacing: 6) {
            art(20)
            Text(privacy.title).font(.system(size: 11.5, weight: .medium)).frame(minWidth: 40, alignment: .leading)
            MiniSwitch(isOn: privacy.isHidden, locked: privacy == .unavailable)
        }
        .padding(.leading, 6)
        .padding(.trailing, 5)
        .frame(height: 28)
        .background(hovering ? Theme.subtle : Theme.surface, in: .rect(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.border) }
        .fixedSize()
    }

    private var row: some View {
        HStack(spacing: compact ? 8 : 12) {
            art(compact ? 34 : 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                Text(caption).font(.system(size: 10.5)).foregroundStyle(Theme.tertiary).lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 2)
            MiniSwitch(isOn: privacy.isHidden, locked: privacy == .unavailable)
        }
        .padding(.leading, compact ? 8 : 10)
        .padding(.trailing, compact ? 9 : 12)
        .frame(maxWidth: .infinity, minHeight: compact ? 50 : 60)
        .background(hovering ? Theme.subtle : Theme.surface, in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(privacy.isHidden ? Theme.border : Theme.warning.opacity(0.4)) }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Hiding is not available").font(.system(size: 12.5, weight: .bold))
            Text("Your plan or your administrator does not allow hiding. Pro and Max include it when it is switched on.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            Button("See plans") { explaining = false; model.openSettings() }.buttonStyle(.expo(.primary, compact: true))
        }
        .padding(14)
        .frame(width: 240, alignment: .leading)
        .foregroundStyle(Theme.text)
    }
}

/// Drawn by hand so it looks the same in floating windows that never take focus.
private struct MiniSwitch: View {
    var isOn: Bool
    var locked: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Theme.accent : Theme.border)
            .frame(width: 30, height: 18)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? Theme.onAccent : Color.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                    .overlay {
                        if locked { Image(systemName: "lock.fill").font(.system(size: 7, weight: .bold)).foregroundStyle(.gray) }
                    }
                    .padding(2)
            }
            .opacity(locked ? 0.7 : 1)
    }
}
