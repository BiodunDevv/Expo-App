import SwiftUI

/// The bottom of the window: the session menu, answering, the screen, privacy,
/// options, listening, ending, the window's size, and the chat.
struct SessionToolbar: View {
    @Environment(AppModel.self) private var model
    let composer: Composer
    let overlays: OverlayController
    @Binding var showingOptions: Bool
    @State private var confirmingEnd = false

    private var assist: AssistController { model.assist }
    private var snapshot: AssistSnapshot { assist.snapshot }

    var body: some View {
        Group {
            if confirmingEnd { endConfirmation }
            else {
                // The word beside the answers button gives way when space is short.
                ViewThatFits(in: .horizontal) {
                    row(compact: false)
                    row(compact: true)
                }
            }
        }
        .frame(height: 47)
        .padding(.horizontal, 12)
        .contentShape(.rect)
    }

    private var endConfirmation: some View {
        HStack(spacing: 8) {
            if let session = assist.currentSession {
                EmailChoice(isOn: Binding(
                    get: { session.emailNotes ?? model.state.settings.emailNotes },
                    set: { model.setEmailNotes($0, for: session.id) }), compact: true)
            } else {
                Text("End this session?").font(.system(size: 12, weight: .medium))
            }
            Spacer(minLength: 4)
            Button("Keep listening") { confirmingEnd = false }.buttonStyle(.expo(.secondary, compact: true))
            AsyncButton(title: "End", busyTitle: "Ending…", kind: .danger, compact: true) {
                await model.endAssist()
                confirmingEnd = false
            }
        }
    }

    private func row(compact: Bool) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                SessionMenu(overlays: overlays, confirmingEnd: $confirmingEnd)
                Button {
                    model.layout.asked()
                    Task { await assist.suggest() }
                } label: {
                    HStack(spacing: 7) {
                        Text("Answer").font(.system(size: 12, weight: .semibold))
                        if !compact { KeyCap("⌘"); KeyCap("↩") }
                    }
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 10))
                    .contentShape(.rect)
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .disabled(assist.isAsking)
                .hint("What should I say? (⌘↩)")
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                tool(composer.capturing ? "photo.fill" : "photo", "Screen capture", on: composer.capturing,
                     help: "Capture your screen and answer it (⇧⌘↩)") { composer.setCapturing(!composer.capturing) }
                tool(model.capturePrivacy.isHidden ? "eye.slash" : "eye", "Hide from screen sharing", on: model.capturePrivacy.isHidden,
                     help: model.capturePrivacy.detail) { model.setHiddenFromCapture(!model.capturePrivacy.isHidden) }
                    .disabled(model.capturePrivacy == .unavailable)
                    .accessibilityValue(model.capturePrivacy.detail)
                tool("slider.horizontal.3", "Options", on: showingOptions, help: "Ways to ask, answer style and see-through") { showingOptions.toggle() }
                Rectangle().fill(Glass.line).frame(width: 1, height: 18).padding(.horizontal, 4)
                listening
                tool("stop.circle", "End session", on: false, help: "End the session") { confirmingEnd = true }
                    .foregroundStyle(Theme.danger)
            }
            .fixedSize()
            Spacer(minLength: 8)
            tool(model.sessionIsSmall ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left",
                 model.sessionIsSmall ? "Restore size" : "Small size", on: false,
                 help: model.sessionIsSmall ? "Back to your size" : "Shrink to the small size") { overlays.toggleSmallSize() }
            tool("minus", "Minimize", on: false, help: "Make this a small “in progress” note") { model.minimizeSession() }
            chatButton(compact: compact)
        }
    }

    /// Bars that follow the voice; a click pauses or resumes listening.
    private var listening: some View {
        let live = snapshot.lifecycle == .listening
        return tool(live ? "waveform" : "pause.fill", live ? "Pause listening" : "Resume listening", on: false,
                    level: live ? assist.level : nil, help: "\(stateLabel) · \(clock(snapshot.elapsedSeconds))") {
            Task { if live { await assist.pause() } else if snapshot.lifecycle == .paused { await model.resumeAssist() } else { await assist.retryListening() } }
        }
        .foregroundStyle(live ? Theme.text : Theme.warning)
    }

    /// Opens or hides the whole conversation under the input.
    private func chatButton(compact: Bool) -> some View {
        let open = model.layout.chatOpen
        return Button { if open { model.layout.hideChat() } else { model.layout.showChat() } } label: {
            HStack(spacing: 7) {
                if !compact { Text(open ? "Hide chat" : "Show chat").font(.system(size: 12, weight: .semibold)) }
                KeyCap(symbol: open ? "chevron.up" : "chevron.down")
            }
            .frame(minWidth: 30, minHeight: 30)
            .contentShape(.rect)
            .fixedSize()
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.secondary)
        .hint(open ? "Hide the chat" : "Show the whole chat")
        .accessibilityLabel(open ? "Hide chat" : "Show chat")
    }

    private func tool(_ symbol: String, _ label: String, on: Bool, level: Double? = nil, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let level { Image(systemName: symbol, variableValue: 0.2 + level * 0.8) }
                else { Image(systemName: symbol) }
            }
            .font(.system(size: 14.5, weight: .medium))
            .frame(width: 32, height: 32)
            .background(on ? Color.white.opacity(0.14) : .clear, in: .rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(on ? Theme.text : Theme.secondary)
        .hint(help)
        .accessibilityLabel(label)
    }

    private var stateLabel: String {
        switch snapshot.lifecycle {
        case .connecting: "Connecting…"
        case .paused: "Paused"
        case .generatingNotes, .ending: "Ending…"
        case .error: "Needs attention"
        default:
            if let attempt = snapshot.recoveryAttempt { "Reconnecting \(attempt)/\(snapshot.recoveryMaxAttempts ?? 5)" }
            else if snapshot.audio == .unavailable { "Audio unavailable" }
            else if snapshot.connection == .offline { "Offline" }
            else { assist.isPractice ? "Practising" : "Listening" }
        }
    }
}

/// A keyboard key, drawn small.
struct KeyCap: View {
    private var text: String?
    private var symbol: String?
    init(_ text: String) { self.text = text }
    init(symbol: String) { self.symbol = symbol }

    var body: some View {
        Group {
            if let symbol { Image(systemName: symbol) } else { Text(text ?? "") }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.secondary)
        .frame(minWidth: 22, minHeight: 22)
        .background(Color.white.opacity(0.1), in: .rect(cornerRadius: 7))
    }
}
