import SwiftUI
import ThinkingOrbsKit

struct DockView: View {
    @Environment(AppModel.self) private var model
    let overlays: OverlayController
    @State private var confirmingEnd = false

    private var snapshot: AssistSnapshot { model.assist.snapshot }

    var body: some View {
        Group {
            if !model.overlaysEligible { signedOut }
            else if !model.assist.isActive { idle }
            else if model.dockMinimized { mini }
            else {
                // Full labels when they fit, icons when the bar is narrow.
                ViewThatFits(in: .horizontal) {
                    activeBar(compact: false)
                    activeBar(compact: true)
                }
            }
        }
        .movesWindow(overlays, .dock)
        .foregroundStyle(Theme.text)
        .background(Theme.surface.opacity(0.98), in: .rect(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(Theme.border) }
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
                Button { overlays.closeDock() } label: { Image(systemName: "xmark").frame(width: 24, height: 24).contentShape(.rect) }
                    .buttonStyle(.plain).foregroundStyle(Theme.secondary).accessibilityLabel("Close")
            }
            HStack(spacing: 9) {
                ChoiceCard(icon: "mic", title: "New session", detail: "Listen and help live") {
                    overlays.closeDock()
                    model.requestAssistStart()
                }
                ChoiceCard(icon: "practice", title: "Practice", detail: "Rehearse first") {
                    overlays.closeDock()
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
                .help("Turn the floating bot off")
            }
            Hairline()
            HStack {
                Button("Open Expo") { overlays.closeDock(); model.showMainWindow() }.buttonStyle(.expo(.plain, compact: true))
                Spacer()
                Button("Settings") { overlays.closeDock(); model.openSettings() }.buttonStyle(.expo(.plain, compact: true))
            }
        }
        .padding(14)
    }

    /// The Assist bar folded away: state, time and a way back.
    private var mini: some View {
        HStack(spacing: 9) {
            Logo(size: 28)
            if !needsRetry && snapshot.lifecycle == .listening { VoiceOrb(level: model.assist.level, size: 24) }
            else { PulseDot(color: Theme.warning, pulsing: false) }
            Text(clock(snapshot.elapsedSeconds)).font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
            Spacer(minLength: 0)
            Button { overlays.setDockMinimized(false); overlays.showAssistant() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .buttonStyle(.expo(.secondary, compact: true)).help("Open").accessibilityLabel("Open the Assist bar")
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
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

    private var needsRetry: Bool {
        snapshot.connection != .connected || snapshot.audio == .unavailable || snapshot.audio == .denied
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
            else { model.assist.isPractice ? "Practising" : "Listening" }
        }
    }

    private var audioLabel: String {
        switch snapshot.audio {
        case .ready: "Audio ready"
        case .silent: "Audio quiet"
        case .denied: "Audio permission"
        case .unavailable: "Audio unavailable"
        case .unknown: "Checking audio"
        }
    }

    private func activeBar(compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 9) {
            Logo(size: compact ? 26 : 30)
            if confirmingEnd {
                Text("End this session and prepare notes?").font(.system(size: 12, weight: .medium))
                Spacer()
                Button("Keep listening") { confirmingEnd = false }.buttonStyle(.expo(.secondary, compact: true))
                AsyncButton(title: "End Assist", busyTitle: "Ending…", kind: .danger, compact: true) {
                    await model.endAssist()
                    confirmingEnd = false
                }
            } else {
                if !needsRetry && snapshot.lifecycle == .listening { VoiceOrb(level: model.assist.level, size: compact ? 22 : 28) }
                else { PulseDot(color: Theme.warning, pulsing: false) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(stateLabel).font(.system(size: 12, weight: .semibold))
                    Text("\(clock(snapshot.elapsedSeconds)) · \(audioLabel)").font(.system(size: 10.5)).foregroundStyle(Theme.secondary).monospacedDigit()
                }
                .fixedSize()
                .help(snapshot.error ?? audioLabel)
                if compact {
                    Button { model.setHiddenFromCapture(!model.capturePrivacy.isHidden) } label: {
                        Image(model.capturePrivacy.isHidden ? "privacy-hidden" : "privacy-visible").resizable().scaledToFit().frame(width: 18, height: 18)
                    }
                    .buttonStyle(.expo(.secondary, compact: true))
                    .disabled(model.capturePrivacy == .unavailable)
                    .help(model.capturePrivacy.detail)
                    .accessibilityLabel("Hide from screen sharing")
                    .accessibilityValue(model.capturePrivacy.detail)
                } else {
                    PrivacyToggle()
                }
                Spacer()
                if snapshot.lifecycle == .paused || snapshot.lifecycle == .error {
                    AsyncButton(title: snapshot.lifecycle == .paused ? "Resume" : "Retry", kind: .secondary, compact: true) {
                        if snapshot.lifecycle == .paused { await model.resumeAssist() } else { await model.assist.retryListening() }
                    }
                } else if needsRetry {
                    AsyncButton(title: "Retry listening", kind: .secondary, compact: true) { await model.assist.retryListening() }
                }
                Button { Task { await model.assist.setAutoAnswer(!model.assist.autoAnswer) } } label: {
                    HStack(spacing: 5) {
                        Icon8(model.assist.autoAnswer ? "bot" : "resume", size: 17)
                        if !compact { Text(model.assist.autoAnswer ? "Auto" : "Transcript") }
                    }
                }
                .buttonStyle(.expo(.secondary, compact: true))
                .fixedSize()
                .help(model.assist.autoAnswer ? "Auto answer is on. Click to only save the transcript." : "Only saving the transcript. Click to answer automatically.")
                Button { overlays.toggleAssistant() } label: {
                    if compact { Icon8("chat", size: 17) }
                    else { Label { Text("Ask Expo") } icon: { Icon8("star", size: 15) } }
                }
                .buttonStyle(.expo(compact ? .secondary : .primary, compact: true)).fixedSize()
                .help("Show or hide the conversation").accessibilityLabel("Ask Expo")
                Menu {
                    Button("Open conversation") { overlays.showAssistant() }
                    if snapshot.lifecycle == .listening { Button("Pause listening") { Task { await model.assist.pause() } } }
                    Button("Retry listening") { Task { await model.assist.retryListening() } }
                    Button("Audio settings") { model.openSettings() }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28).accessibilityLabel("More options")
                Button { overlays.setDockMinimized(true) } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                    .buttonStyle(.expo(.secondary, compact: true)).help("Shrink").accessibilityLabel("Shrink the Assist bar")
                Button { confirmingEnd = true } label: { Image(systemName: "stop.fill") }
                    .buttonStyle(.expo(.danger, compact: true)).accessibilityLabel("End Assist")
            }
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
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
            .background(hovering ? Theme.selected : Theme.background, in: .rect(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(hovering ? Theme.tertiary : Theme.border) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.3, bounce: 0.4), value: hovering)
    }
}

/// Shows that Expo is listening.
struct PulseDot: View {
    var color: Color
    var pulsing: Bool
    @State private var wide = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .background {
                if pulsing && !reduceMotion {
                    Circle().fill(color.opacity(0.35))
                        .scaleEffect(wide ? 2.4 : 1).opacity(wide ? 0 : 1)
                        .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: wide)
                        .onAppear { wide = true }
                }
            }
            .accessibilityHidden(true)
    }
}
