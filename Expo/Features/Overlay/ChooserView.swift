import SwiftUI

/// Opened from the floating bot between sessions.
struct ChooserView: View {
    @Environment(AppModel.self) private var model
    let overlays: OverlayController
    @State private var confirming = false

    var body: some View {
        Group {
            if !model.overlaysEligible { signedOut }
            else if confirming {
                StartMeetingConfirmation(cancel: { confirming = false }, started: { confirming = false })
                    .padding(18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { idle }
        }
        .onChange(of: model.assist.isActive) { confirming = false }
        .movesWindow(overlays, .chooser)
        .foregroundStyle(Theme.text)
        .glassCard(radius: 24)
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Opened from the floating bot: what would you like to do?
    private var idle: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                Logo(size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("What shall we do?").font(.system(size: 13.5, weight: .bold))
                    Text("Drag me anywhere").font(.system(size: 10.5)).foregroundStyle(Theme.tertiary)
                }
                Spacer()
                Button { overlays.closeChooser() } label: { Image(systemName: "xmark").frame(width: 24, height: 24).contentShape(.rect) }
                    .buttonStyle(.plain).foregroundStyle(Theme.secondary).accessibilityLabel("Close")
            }
            HStack(spacing: 9) {
                ChoiceCard(icon: "mic", title: "Start meeting", detail: "Listen and help live") {
                    confirming = true
                }
                ChoiceCard(icon: "practice", title: "Practice", detail: "Rehearse first") {
                    overlays.closeChooser()
                    model.open(.practice)
                }
            }
            if let toast = model.toasts.last(where: \.isError) {
                Text(toast.message).font(.system(size: 11)).foregroundStyle(Theme.danger).lineLimit(2)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                PrivacyToggle()
                Spacer()
                Toggle("Floating bot", isOn: Binding(get: { model.showsFloatingButton }, set: { on in
                    if !on { overlays.hideFloatingBot() }
                }))
                .toggleStyle(.switch).controlSize(.mini).font(.system(size: 11, weight: .medium)).fixedSize()
                .hint("Turn the floating bot off")
            }
            Hairline()
            HStack {
                Button("Open Expo") { overlays.closeChooser(); model.showMainWindow() }.buttonStyle(.expo(.plain, compact: true))
                Spacer()
                Button("Settings") { overlays.closeChooser(); model.openSettings() }.buttonStyle(.expo(.plain, compact: true))
            }
        }
        .padding(14)
    }

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RobotMark(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Expo").font(.system(size: 13, weight: .bold))
                    Text(model.isSignedIn ? "Finish setting up" : "Not signed in").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                PrivacyToggle()
            }
            Text("Choose whether Expo appears in screen shares. You can change this at any time.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(model.isSignedIn ? "Continue setup" : "Sign in") { model.showMainWindow() }
                .buttonStyle(.expo(.primary, compact: true))
        }
        .padding(13)
    }
}

/// One of the two ways to begin.
private struct ChoiceCard: View {
    var icon: String
    var title: String
    var detail: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Icon8(icon, size: 34).scaleEffect(hovering ? 1.12 : 1)
                Text(title).font(.system(size: 12.5, weight: .bold))
                Text(detail).font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(hovering ? Glass.selected : Glass.fill, in: .rect(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).stroke(hovering ? Theme.tertiary : Glass.line) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.3, bounce: 0.4), value: hovering)
    }
}
