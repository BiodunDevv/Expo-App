import SwiftUI

/// The session made small: that a meeting is going on, for how long, and the
/// way back to the chat.
struct CompactSession: View {
    @Environment(AppModel.self) private var model
    let overlays: OverlayController

    static let size = NSSize(width: 332, height: 52)

    private var assist: AssistController { model.assist }

    var body: some View {
        let snapshot = assist.snapshot
        let listening = snapshot.lifecycle == .listening
        let paused = snapshot.lifecycle == .paused
        let trouble = snapshot.lifecycle == .error || snapshot.connection == .offline
            || snapshot.audio == .unavailable || snapshot.audio == .denied || model.toasts.contains(where: \.isError)
        HStack(spacing: 10) {
            Image(systemName: paused ? "pause.fill" : "waveform", variableValue: listening ? 0.2 + assist.level * 0.8 : 1)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(paused || trouble ? Theme.warning : Theme.success)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title(paused: paused)).font(.system(size: 12.5, weight: .bold)).lineLimit(1)
                Text(detail(trouble: trouble))
                    .font(.system(size: 10.5, weight: .medium)).monospacedDigit().lineLimit(1)
                    .foregroundStyle(trouble ? Theme.warning : Theme.secondary)
            }
            Spacer(minLength: 4)
            Button { model.layout.showChat() } label: {
                Label("Show chat", systemImage: "chevron.down")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 11).frame(height: 30)
                    .background(Theme.accent, in: .capsule)
                    .contentShape(.capsule)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .hint("Open the input and the chat")
        }
        .padding(.leading, 12).padding(.trailing, 10)
        .frame(width: Self.size.width, height: Self.size.height)
        .movesWindow(overlays, .session)
        .glassCard(radius: Self.size.height / 2)
        .accessibilityElement(children: .contain)
    }

    private func title(paused: Bool) -> String {
        let what = assist.isPractice ? "Practice" : "Meeting"
        return paused ? "\(what) paused" : "\(what) in progress"
    }

    private func detail(trouble: Bool) -> String {
        if trouble { return "Open to see what needs attention" }
        let time = clock(assist.snapshot.elapsedSeconds)
        if assist.isAsking { return "\(time) · Answering…" }
        let new = model.visibleAnswers.count - model.layout.answersAtMinimize
        return new > 0 ? "\(time) · \(new) new answer\(new == 1 ? "" : "s")" : time
    }
}
