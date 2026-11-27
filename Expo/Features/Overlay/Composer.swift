import SwiftUI

/// What is in the input, and what pressing return does. Shared by the input row
/// and the toolbar.
@MainActor
@Observable
final class Composer {
    var question = "" {
        didSet {
            // Editing takes heard words over, so they are not also sent by themselves.
            guard !filled.isEmpty, question != filled else { return }
            filled = ""
            model?.assist.forgetHeard()
        }
    }
    /// The text Expo put in the box from what it heard.
    private(set) var filled = ""
    private(set) var capturing = false
    private(set) var sources: [ScreenSource] = []
    /// Nil is the entire screen.
    var sourceID: String?

    @ObservationIgnored private weak var model: AppModel?

    var source: ScreenSource? { sources.first { $0.id == sourceID } }
    /// Words the person typed, as opposed to ones still being heard.
    var typed: String { question == filled ? "" : question.trimmed }

    func attach(_ model: AppModel) { self.model = model }

    func hear(_ live: String, model: AppModel) {
        self.model = model
        guard question.isEmpty || question == filled else { return }
        filled = live
        question = live
    }

    func dropHeard() {
        filled = ""
        question = ""
        model?.assist.forgetHeard()
    }

    func setCapturing(_ on: Bool) {
        capturing = on
        // Capture always starts on the entire screen.
        sourceID = nil
        // Screen permission is only requested once the person chooses to capture.
        if on { Task { await loadSources(prompt: true) } }
    }

    /// With nothing typed, answers whatever is on screen; otherwise the typed question.
    func capture() {
        guard let assist = model?.assist else { return }
        model?.layout.asked()
        let text = typed
        if !filled.isEmpty { dropHeard() }
        if text.isEmpty {
            assist.captureAndAnswer(sourceID: sourceID, source: source.map { "“\($0.name)”" } ?? "the entire screen")
        } else if !assist.isAsking {
            question = ""
            assist.submit(text, withScreen: true, sourceID: sourceID)
        }
    }

    func send() {
        guard let assist = model?.assist, !assist.isAsking else { return }
        if capturing { capture(); return }
        let text = question
        guard !text.trimmed.isEmpty else { return }
        model?.layout.asked()
        if !filled.isEmpty { assist.forgetHeard() }
        filled = ""
        question = ""
        assist.submit(text)
    }

    func loadSources(prompt: Bool = false) async {
        guard prompt || CGPreflightScreenCaptureAccess() else { return }
        do { sources = try await ScreenContextCapture.sources() }
        catch { sources = []; if prompt { model?.report(error) } }
        if !sources.contains(where: { $0.id == sourceID }) { sourceID = nil }
    }
}
