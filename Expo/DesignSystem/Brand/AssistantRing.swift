import SwiftUI
import VoiceRingKit

/// Expo's voice: the Libraries.dev voice ring, moved by the audio already being
/// captured. It never opens an audio source itself.
struct AssistantRing: View {
    @Environment(AppModel.self) private var model
    var size: CGFloat

    var body: some View {
        let assist = model.assist!
        let listening = assist.snapshot.lifecycle == .listening
        var style = VoiceStyle()
        style.theme = .dark
        // A quiet ring is held still, so it costs nothing while nobody speaks.
        style.paused = !assist.isAsking && assist.level < 0.03
        return VoiceRing(.ring, state: assist.isAsking ? .processing : listening ? .listening : .idle,
                         source: .level { assist.level }, style: style, size: size)
            .frame(width: size, height: size)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
