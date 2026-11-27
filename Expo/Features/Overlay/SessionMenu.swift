import SwiftUI

/// The mark at the bottom left: pause, retry, open Expo, hide or end. Kept apart
/// from the toolbar so the ticking clock and the voice never redraw an open menu,
/// which closes it.
struct SessionMenu: View {
    @Environment(AppModel.self) private var model
    let overlays: OverlayController
    @Binding var confirmingEnd: Bool

    var body: some View {
        let assist = model.assist!
        let lifecycle = assist.lifecycle
        Menu {
            if lifecycle == .listening { Button("Pause listening") { Task { await assist.pause() } } }
            if lifecycle == .paused { Button("Resume listening") { Task { await model.resumeAssist() } } }
            Button("Retry listening") { Task { await assist.retryListening() } }
            Divider()
            Button("Open Expo") { model.showMainWindow() }
            Button("Settings") { model.openSettings() }
            Button("Minimize") { model.minimizeSession() }
            Button("Hide this window") { overlays.hideAssistant() }
            Divider()
            Button("End session…") { confirmingEnd = true }
        } label: {
            Logo(size: 24)
        }
        .menuStyle(.button).buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .hint("Session")
        .accessibilityLabel("Session")
    }
}
