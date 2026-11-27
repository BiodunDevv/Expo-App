import SwiftUI

// The transcript being saved while Expo listens.

/// Everything heard in this session, newest at the bottom.
struct LiveTranscript: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let session = model.assist.currentSession
        let segments = Array(session?.transcript.suffix(200) ?? [])
        let preview = model.assist.preview
        VStack(spacing: 0) {
            if let count = session?.transcript.count, count > 0 {
                Label("\(count) line\(count == 1 ? "" : "s") saved", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.success)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 14).padding(.top, 4)
            }
            if segments.isEmpty && preview == nil {
                VStack(spacing: 4) {
                    Text("Listening for the first words").font(.system(size: 14, weight: .semibold))
                    Text("Everything said is saved to History when you end the session.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                .multilineTextAlignment(.center)
                .textHalo()
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                FollowingScroll(count: session?.transcript.count ?? 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(segments) { LiveLine(speaker: $0.speaker, time: $0.at, text: $0.text) }
                        if let preview {
                            LiveLine(speaker: preview.source == "microphone" ? "You" : "…", time: "", text: preview.text, pending: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .animation(.snappy(duration: 0.2), value: segments.count)
    }
}

private struct LiveLine: View {
    var speaker: String
    var time: String
    var text: String
    var pending = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if speaker == ScreenAnswer.speaker {
                Image(systemName: "camera.viewfinder").frame(width: 20, height: 20).foregroundStyle(Theme.secondary)
            } else {
                Icon8(speaker == "You" ? "mic" : "audio", size: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(speaker).font(.system(size: 11, weight: .bold))
                    Text(time).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.tertiary)
                }
                Text(text).font(.system(size: 12.5)).italic(pending)
                    .lineLimit(speaker == ScreenAnswer.speaker ? 3 : nil)
                    .foregroundStyle(pending ? Theme.tertiary : Theme.text)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
        .textHalo()
        .transition(.opacity.combined(with: .offset(y: 6)))
    }
}
