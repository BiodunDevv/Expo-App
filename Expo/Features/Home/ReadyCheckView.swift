import AVFoundation
import SwiftUI

extension AppModel {
    /// The current facts, read live from macOS where macOS can answer.
    var readiness: Readiness {
        // Reading this makes views refresh after the person returns from System Settings.
        _ = permissionRevision
        let microphone: Readiness.Permission = switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
        return Readiness(.init(
            consent: state.consent.transcriptCapture.granted,
            audioTest: audioTest,
            microphoneWanted: state.settings.captureMicrophone,
            microphone: microphone,
            screenAllowed: CGPreflightScreenCaptureAccess(),
            serviceReachable: health.backend == .reconnecting ? nil : health.backend == .connected,
            assistantReady: health.assistantReady,
            transcriptionReady: health.transcriptionReady
        ))
    }
}

/// One place to see, and fix, everything a session depends on.
struct ReadyCheckCard: View {
    @Environment(AppModel.self) private var model
    @State private var busy: Readiness.Kind?
    @State private var showAll = false

    var body: some View {
        let readiness = model.readiness
        Card {
            HStack(spacing: 10) {
                Image(systemName: readiness.blockers.isEmpty ? (readiness.isChecking ? "clock" : "checkmark.circle.fill") : "exclamationmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(readiness.blockers.isEmpty ? (readiness.isChecking ? Theme.secondary : Theme.success) : Theme.warning)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ready check").font(.system(size: 14.5, weight: .bold))
                    Text(readiness.headline).font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                if readiness.blockers.isEmpty && !readiness.isChecking {
                    Button(showAll ? "Hide details" : "Show details") { withAnimation(.snappy) { showAll.toggle() } }
                        .buttonStyle(.expo(.plain, compact: true))
                }
                AsyncButton(title: "Refresh", busyTitle: "Checking…", kind: .plain, compact: true) {
                    model.permissionsMayHaveChanged()
                    await model.refreshHealth()
                }
            }
            if showAll || !readiness.blockers.isEmpty || readiness.isChecking {
                VStack(spacing: 0) {
                    ForEach(readiness.items) { item in
                        Hairline()
                        row(item)
                    }
                }
            }
            Text("⌘↩ Ask Expo · ⇧⌘↩ Ask about your screen").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.permissionsMayHaveChanged()
        }
    }

    private func row(_ item: Readiness.Item) -> some View {
        HStack(spacing: 11) {
            Icon8(symbol(item.kind), size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 12.5, weight: .semibold))
                Text(item.detail).font(.system(size: 11.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let fix = item.fix {
                Button(busy == item.kind ? "Working…" : fix) { perform(item) }
                    .buttonStyle(.expo(item.state == .action && item.required ? .primary : .secondary, compact: true))
                    .disabled(busy != nil || (item.kind == .computerAudio && (model.assist.isActive || !model.state.consent.transcriptCapture.granted)))
            }
            Image(systemName: mark(item.state).symbol)
                .font(.system(size: 13))
                .foregroundStyle(mark(item.state).color)
                .frame(width: 18)
                .accessibilityLabel(mark(item.state).label)
        }
        .padding(.vertical, 9)
    }

    private func symbol(_ kind: Readiness.Kind) -> String {
        switch kind {
        case .consent: "shield"
        case .computerAudio: "audio"
        case .microphone: "mic"
        case .screen: "app"
        case .service: "bot"
        }
    }

    private func mark(_ state: Readiness.State) -> (symbol: String, color: Color, label: String) {
        switch state {
        case .ready: ("checkmark.circle.fill", Theme.success, "Ready")
        case .action: ("exclamationmark.circle.fill", Theme.warning, "Needs attention")
        case .checking: ("clock", Theme.tertiary, "Checking")
        case .off: ("minus.circle", Theme.tertiary, "Optional, off")
        }
    }

    private func perform(_ item: Readiness.Item) {
        busy = item.kind
        Task {
            defer { busy = nil; model.permissionsMayHaveChanged() }
            switch item.kind {
            case .consent:
                // Consent is always a deliberate choice made beside its explanation.
                model.openSettings()
            case .computerAudio:
                let result = await model.runAudioTest()
                if result.passed { model.notify(result.message) } else { model.report(BackendError(result.message)) }
            case .microphone:
                if !model.state.settings.captureMicrophone { model.updateSettings { $0.captureMicrophone = true } }
                else if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .audio) }
                else { AudioTestRow.open("Privacy_Microphone") }
            case .screen:
                if !CGRequestScreenCaptureAccess() { AudioTestRow.open("Privacy_ScreenCapture") }
            case .service:
                await model.refreshHealth()
            }
        }
    }
}
