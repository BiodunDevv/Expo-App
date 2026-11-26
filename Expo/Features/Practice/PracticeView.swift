import SwiftUI

/// Rehearse with a live session: Expo listens and answers on screen exactly as
/// it does in a real one.
struct PracticeView: View {
    @Environment(AppModel.self) private var model
    @State private var kind = PracticeKind.interview
    @State private var topic = ""
    @State private var starting = false
    @State private var message = ""

    /// Finished practice only; the one running has its own card above.
    private var past: [ExpoSession] {
        model.state.sessions
            .filter { $0.deletedAt == nil && $0.id != model.state.activeSessionId && PracticeSession.isPractice($0.title) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private var running: Bool { model.assist.isActive }

    var body: some View {
        Page(title: "Practice", subtitle: "Rehearse live, before the real conversation.", art: "art-practice") {
            if running { runningCard } else { setup }
            Card(title: "Past practice", icon: "history") {
                if past.isEmpty {
                    EmptyScene(animation: "calendar", title: "No practice yet",
                               detail: "Each session keeps its transcript, answers and notes here.") { EmptyView() }
                } else {
                    VStack(spacing: 0) {
                        ForEach(past.prefix(8)) { session in
                            if session.id != past.first?.id { Hairline() }
                            SessionRow(session: session) { model.route = .history; model.selectedSessionID = session.id }
                        }
                    }
                }
            }
        }
    }

    private var setup: some View {
        Card(title: "New practice session", icon: "practice") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                ForEach(PracticeKind.allCases) { option in
                    let chosen = kind == option
                    Button { kind = option } label: {
                        VStack(spacing: 7) {
                            Icon8(option.icon, size: 34)
                            Text(option.title).font(.system(size: 12, weight: chosen ? .bold : .medium))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(chosen ? Theme.selected : Theme.surface, in: .rect(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).stroke(chosen ? Theme.accent : Theme.border, lineWidth: chosen ? 2 : 1) }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("\(kind.topicPrompt) (optional)").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.secondary)
                TextEditor(text: $topic)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 78)
                    .background(Theme.surface, in: .rect(cornerRadius: 9))
                    .overlay { RoundedRectangle(cornerRadius: 9).stroke(Theme.border) }
                    .accessibilityLabel(kind.topicPrompt)
                    .onChange(of: topic) {
                        if topic.count > 8_000 { topic = String(topic.prefix(8_000)) }
                    }
                if !model.state.settings.savedBrief.isEmpty {
                    Button("Use my saved meeting brief") { topic = model.state.settings.savedBrief }
                        .buttonStyle(.expo(.plain, compact: true))
                }
            }
            HStack(alignment: .top, spacing: 14) {
                step("mic", "Ask or play a question", "Say it aloud, or play a video or call")
                step("bot", "See an answer", "It appears on screen as you go")
                step("resume", "Review after", "Transcript and notes are saved")
            }
            if let blocker = model.readiness.blockers.first {
                Text("\(blocker.title): \(blocker.detail)").font(.system(size: 12)).foregroundStyle(Theme.warning)
            }
            if !message.isEmpty { Text(message).font(.system(size: 12)).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true) }
            Button(action: start) {
                Label { Text(starting ? "Starting…" : "Start practice") } icon: { Icon8("practice", size: 16) }
            }
            .buttonStyle(.expo)
            .disabled(starting)
        }
    }

    private var runningCard: some View {
        let practising = model.assist.isPractice
        return Card(title: practising ? "Practice is running" : "A session is running", icon: "practice") {
            Text(practising ? "Ask a question aloud and watch the answer appear." : "End it before starting a practice session.")
                .font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
            HStack(spacing: 8) {
                Button("Open conversation") { model.requestAssistStart() }.buttonStyle(.expo)
                AsyncButton(title: practising ? "End practice" : "End Assist", busyTitle: "Ending…", kind: .secondary) { await model.endAssist() }
            }
        }
    }

    private func step(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Icon8(icon, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func start() {
        starting = true
        message = ""
        Task {
            do { try await model.startPractice(kind, topic: topic) }
            catch { message = userMessage(error, fallback: "Expo couldn't start listening. Check your audio settings and try again.") }
            starting = false
        }
    }
}
