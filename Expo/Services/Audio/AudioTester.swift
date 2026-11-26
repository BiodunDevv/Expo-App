import Foundation

struct AudioTestResult: Sendable {
    var passed: Bool
    var microphone: Bool
    var message: String
}

/// Captures three seconds of audio, reports what came through, and discards it.
@MainActor
enum AudioTester {
    static func run(settings: ExpoSettings) async -> AudioTestResult {
        let capture = AudioCaptureService()
        defer { capture.stop() }
        do {
            let microphone = try await capture.start(settings: settings) { _ in }
            // A sound from another process proves computer audio really reaches Expo:
            // without permission, macOS delivers silence rather than an error.
            let tone = playTestSound()
            defer { tone?.terminate() }
            try await Task.sleep(for: .seconds(3))
            let heard = (capture.health?.secondsSinceSystemSound ?? .infinity) < 2.8
            var message = heard
                ? "Audio test passed. The sample was discarded."
                : "Expo heard nothing. Allow Expo under Screen & System Audio Recording, check your output device, then test again."
            if settings.captureMicrophone && !microphone { message += " The microphone is unavailable." }
            return AudioTestResult(passed: heard, microphone: microphone, message: message)
        } catch {
            return AudioTestResult(passed: false, microphone: false, message: userMessage(error))
        }
    }

    private static func playTestSound() -> Process? {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", "for i in 1 2 3; do /usr/bin/afplay -v 0.4 /System/Library/Sounds/Glass.aiff; done"]
        do { try process.run() } catch { return nil }
        return process
    }
}
