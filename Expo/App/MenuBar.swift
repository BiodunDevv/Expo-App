import AppKit
import SwiftUI

/// The menu behind the menu bar icon.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    let delegate: AppDelegate

    private var recent: [ExpoSession] {
        Array(model.state.sessions.filter { $0.deletedAt == nil }.sorted { $0.startedAt > $1.startedAt }.prefix(5))
    }

    private func status(_ session: ExpoSession) -> MenuStatusLabel {
        let title = session.title.count > 42 ? String(session.title.prefix(41)) + "…" : session.title
        if session.notesStatus == "failed" { return MenuStatusLabel(title: title, symbol: "xmark.circle.fill", color: .systemRed) }
        if session.status != "complete" { return MenuStatusLabel(title: title, symbol: "clock.fill", color: .systemGray) }
        return MenuStatusLabel(title: title, symbol: "checkmark.circle.fill", color: .systemGreen)
    }

    var body: some View {
        if model.overlaysEligible {
            if model.assist.isActive {
                Button { delegate.overlays.showAssistant() } label: { MenuStatusLabel(title: "Ask Expo", symbol: "waveform.circle.fill", color: .systemOrange) }
                if model.assist.snapshot.lifecycle == .paused {
                    Button("Resume Assist") { Task { await model.resumeAssist() } }
                } else {
                    Button("Pause Assist") { Task { await model.assist.pause() } }
                    Button("Retry Listening") { Task { await model.assist.retryListening() } }
                }
                Button("End Assist") { Task { await model.endAssist() } }
            } else {
                Button("Start Assist…") { model.requestAssistStart() }
                Button("Practice") { model.open(.practice) }
            }
            if !recent.isEmpty {
                Divider()
                ForEach(recent) { session in
                    Button {
                        model.open(.history)
                        model.selectedSessionID = session.id
                    } label: { status(session) }
                }
            }
            Divider()
        }
        if model.privacyFailure != nil {
            Text("Hiding could not be confirmed")
            Button("Retry Privacy Protection") { model.retryPrivacyProtection() }
        }
        Toggle("Hide from Screen Sharing", isOn: Binding(
            get: { model.phase == .ready && model.capturePrivacy.isHidden },
            set: { model.setHiddenFromCapture($0) }))
            .disabled(model.phase != .ready || model.capturePrivacy == .unavailable)
        Toggle("Show Floating Bot", isOn: Binding(
            get: { model.showsFloatingButton }, set: { model.showsFloatingButton = $0 }))
        Divider()
        Button("Open Expo") { delegate.showMain() }
        if model.overlaysEligible { Button("Settings") { model.openSettings() } }
        Button("Quit Expo") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

/// A menu row with a colored status symbol.
private struct MenuStatusLabel: View {
    var title: String
    var symbol: String
    var color: NSColor

    var body: some View {
        Label {
            Text(title)
        } icon: {
            let configuration = NSImage.SymbolConfiguration(paletteColors: [.white, color])
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
                Image(nsImage: image)
            }
        }
        .labelStyle(.titleAndIcon)
    }
}
