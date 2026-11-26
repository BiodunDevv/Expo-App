import Foundation

/// Whether a session can start well, worked out from plain facts so it can be tested.
struct Readiness: Equatable {
    enum State: Equatable { case ready, action, checking, off }
    enum Kind: String, CaseIterable { case consent, computerAudio, microphone, screen, service }
    enum Permission: Equatable { case granted, notAsked, denied }
    enum AudioTest: Equatable { case never, passed, failed }

    struct Facts: Equatable {
        var consent: Bool
        var audioTest: AudioTest
        var microphoneWanted: Bool
        var microphone: Permission
        var screenAllowed: Bool
        /// nil while still being checked.
        var serviceReachable: Bool?
        var assistantReady: Bool?
        var transcriptionReady: Bool?
    }

    struct Item: Equatable, Identifiable {
        var kind: Kind
        var state: State
        var title: String
        var detail: String
        /// Label of the button that fixes it, if there is something to do.
        var fix: String?
        /// Optional items never stop a session.
        var required: Bool
        var id: Kind { kind }
    }

    var items: [Item]

    var blockers: [Item] { items.filter { $0.required && $0.state == .action } }
    var isChecking: Bool { items.contains { $0.required && $0.state == .checking } }

    var headline: String {
        if !blockers.isEmpty { return blockers.count == 1 ? "1 thing needs attention" : "\(blockers.count) things need attention" }
        return isChecking ? "Checking…" : "Ready to start"
    }

    init(_ facts: Facts) {
        let consent = facts.consent
            ? Item(kind: .consent, state: .ready, title: "Transcript consent", detail: "Granted", required: true)
            : Item(kind: .consent, state: .action, title: "Transcript consent", detail: "Needed before Expo can listen", fix: "Review", required: true)

        let audio: Item = switch facts.audioTest {
        case .passed: Item(kind: .computerAudio, state: .ready, title: "Computer audio", detail: "Expo heard the test sound", fix: "Test again", required: true)
        case .failed: Item(kind: .computerAudio, state: .action, title: "Computer audio", detail: "Expo heard nothing. Check the permission", fix: "Test again", required: true)
        case .never: Item(kind: .computerAudio, state: .action, title: "Computer audio", detail: "Not tested yet", fix: "Test", required: true)
        }

        let microphone: Item = if !facts.microphoneWanted {
            Item(kind: .microphone, state: .off, title: "Microphone", detail: "Off. Only other people are transcribed", fix: "Turn on", required: false)
        } else {
            switch facts.microphone {
            case .granted: Item(kind: .microphone, state: .ready, title: "Microphone", detail: "Allowed", required: false)
            case .notAsked: Item(kind: .microphone, state: .off, title: "Microphone", detail: "macOS will ask when you first use it", fix: "Allow", required: false)
            case .denied: Item(kind: .microphone, state: .action, title: "Microphone", detail: "Blocked in System Settings", fix: "Open Settings", required: false)
            }
        }

        let screen = facts.screenAllowed
            ? Item(kind: .screen, state: .ready, title: "Screen questions", detail: "Allowed", required: false)
            : Item(kind: .screen, state: .off, title: "Screen questions", detail: "Optional. Allow it to ask about your screen", fix: "Allow", required: false)

        let service: Item = switch facts.serviceReachable {
        case nil:
            Item(kind: .service, state: .checking, title: "Expo service", detail: "Connecting…", required: true)
        case false?:
            Item(kind: .service, state: .action, title: "Expo service", detail: "Can’t connect right now", fix: "Check again", required: true)
        case true?:
            if facts.assistantReady == false {
                Item(kind: .service, state: .action, title: "Expo service", detail: "The AI assistant isn’t available", fix: "Check again", required: true)
            } else if facts.transcriptionReady == false {
                Item(kind: .service, state: .action, title: "Expo service", detail: "Live transcription isn’t available", fix: "Check again", required: true)
            } else {
                Item(kind: .service, state: .ready, title: "Expo service", detail: "Connected", required: true)
            }
        }
        items = [consent, audio, microphone, screen, service]
    }
}
