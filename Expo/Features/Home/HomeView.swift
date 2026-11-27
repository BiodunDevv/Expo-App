import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    private var sessions: [ExpoSession] {
        model.state.sessions.filter { $0.deletedAt == nil }.sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero.rise()
                stats.rise(0.06)
                ReadyCheckCard().rise(0.12)
                recentSessions.rise(0.18)
            }
            .frame(maxWidth: 780, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 34)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .task { await model.refreshHealth() }
    }

    private var hero: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    RobotMark(size: 46)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(greeting).font(.system(size: 23, weight: .bold))
                        Text(model.assist.isActive ? "Assist is running" : "Ready for your next conversation?")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
                    }
                }
                Text("Get concise help while Expo quietly follows the conversation.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                if !model.state.consent.transcriptCapture.granted {
                    Text("Transcript consent is off. Turn it on in Settings to start Assist.")
                        .font(.system(size: 12)).foregroundStyle(Theme.warning)
                }
                HStack(spacing: 8) {
                    Button(model.assist.isActive ? "Open conversation" : "Start Assist") { model.requestAssistStart() }
                        .buttonStyle(.expo)
                    if model.assist.isActive {
                        AsyncButton(title: "End Assist", kind: .secondary) { await model.endAssist() }
                    } else {
                        Button { model.open(.practice) } label: { Label { Text("Practise first") } icon: { Icon8("practice", size: 16) } }
                            .buttonStyle(.expo(.secondary))
                    }
                }
                .padding(.top, 3)
            }
            Spacer(minLength: 0)
            LoopingAnimation(name: "auth-hero").frame(width: 176, height: 176)
        }
        .padding(.leading, 20).padding(.trailing, 8).padding(.vertical, 6)
        .background { Wash() }
        .clipShape(.rect(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).stroke(Theme.border) }
    }

    /// Counted from what is stored on this Mac.
    private var stats: some View {
        let minutes = sessions.reduce(0) { $0 + $1.durationSeconds } / 60
        let answers = sessions.reduce(0) { $0 + $1.assistantMessages.count }
        let practice = sessions.filter { PracticeSession.isPractice($0.title) }.count
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 10)], spacing: 10) {
            StatTile(icon: "chat", value: "\(sessions.count)", label: sessions.count == 1 ? "Session" : "Sessions")
            StatTile(icon: "history", value: "\(minutes)", label: "Minutes listened")
            StatTile(icon: "bot", value: "\(answers)", label: "AI answers")
            StatTile(icon: "practice", value: "\(practice)", label: practice == 1 ? "Practice session" : "Practice sessions")
        }
    }

    private var recentSessions: some View {
        Card(title: "Recent sessions", icon: "history") {
            if sessions.isEmpty {
                EmptyScene(animation: "calendar", title: "No sessions yet",
                           detail: "Your notes, decisions and follow-ups will appear here after your first Assist.") {
                    Button("Start your first session") { model.requestAssistStart() }.buttonStyle(.expo(.secondary, compact: true))
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(sessions.prefix(4)) { session in
                        if session.id != sessions.first?.id { Hairline() }
                        SessionRow(session: session) { model.route = .history; model.selectedSessionID = session.id }
                    }
                }
            }
        }
    }

    private var greeting: String {
        let name = model.state.profile.preferredName.nonEmpty ?? model.state.account?.firstName ?? ""
        return name.isEmpty ? "Welcome" : "Hello, \(name)"
    }
}
