import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// Captures three seconds of audio, reports what came through, and discards it.
struct AudioTestRow: View {
    /// Reports whether computer output was captured.
    var onResult: (Bool) -> Void = { _ in }
    @Environment(AppModel.self) private var model
    @State private var result = ""
    @State private var systemReady: Bool?
    @State private var microphoneReady: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                AsyncButton(title: systemReady == nil ? "Test audio" : "Test again", busyTitle: "Listening for 3 seconds…", kind: .secondary, compact: true) { await run() }
                    .disabled(!model.state.consent.transcriptCapture.granted || model.assist.isActive)
                badge("Computer output", systemReady)
                if model.state.settings.captureMicrophone { badge("Microphone", microphoneReady) }
                Spacer()
                Button("Audio settings") { Self.open("Privacy_ScreenCapture") }.buttonStyle(.expo(.plain, compact: true))
                Button("Microphone settings") { Self.open("Privacy_Microphone") }.buttonStyle(.expo(.plain, compact: true))
            }
            if !model.state.consent.transcriptCapture.granted {
                Text("Allow transcript capture in Settings before testing audio.").font(.system(size: 12)).foregroundStyle(Theme.warning)
            } else if !result.isEmpty {
                Text(result).font(.system(size: 12)).foregroundStyle(systemReady == true ? Theme.success : Theme.warning).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func badge(_ label: String, _ ready: Bool?) -> some View {
        if let ready { StatusPill(label: label, color: ready ? Theme.success : Theme.warning) }
    }

    private func run() async {
        result = ""
        let outcome = await model.runAudioTest()
        systemReady = outcome.passed
        microphoneReady = outcome.microphone
        result = outcome.message
        onResult(outcome.passed)
    }

    static func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
}
