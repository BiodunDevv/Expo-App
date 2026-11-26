import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var trash = false
    @State private var cursor: String?
    @State private var matches: [AppModel.Match]?
    @State private var offline = false
    @State private var searching = false
    @State private var restoring: ExpoSession?

    private var sessions: [ExpoSession] {
        model.state.sessions.filter { ($0.deletedAt != nil) == trash }.sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        Page(title: "History", subtitle: "Your conversations, decisions, and follow-ups.", art: "art-review") {
            HStack {
                Field(label: "Search sessions", text: $query)
                Picker("Show", selection: $trash) {
                    Text("Sessions").tag(false)
                    Text("Trash").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 180).padding(.top, 20)
            }
            if offline { Text("You are offline. Results may be incomplete and only cached content can be searched.").font(.system(size: 12)).foregroundStyle(Theme.warning) }
            if trash { Text("Deleted sessions stay in your history so you can restore them.").font(.system(size: 12)).foregroundStyle(Theme.secondary) }
            Card {
                if searching {
                    HStack { ProgressView().controlSize(.small); Text("Searching…") }
                } else if let matches {
                    if matches.isEmpty { empty("No matching sessions", "Try another search, or switch between Sessions and Trash.", art: "magnifyingglass") }
                    ForEach(matches) { match in
                        if let session = model.store.session(match.sessionID) {
                            SessionRow(session: session, detail: "\(match.count) match\(match.count == 1 ? "" : "es") · \(match.snippet)") { open(session) }
                        }
                    }
                } else if sessions.isEmpty {
                    empty(trash ? "Trash is empty" : "No sessions yet", trash ? "Deleted sessions appear here." : "Completed sessions will appear here.", art: "tray")
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(sessions) { session in
                            if session.id != sessions.first?.id { Hairline() }
                            SessionRow(session: session) { open(session) }
                        }
                    }
                    if cursor != nil {
                        AsyncButton(title: "Load more", kind: .secondary) { cursor = await model.loadSessions(trash: trash, cursor: cursor) }
                    }
                }
            }
        }
        .task(id: trash) { cursor = await model.loadSessions(trash: trash) }
        .task(id: "\(trash)|\(query)") {
            guard query.trimmed.count >= 2 else { matches = nil; offline = false; searching = false; return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            searching = true
            do {
                let result = try await model.search(query, trash: trash)
                guard !Task.isCancelled else { return }
                matches = result.matches
                offline = result.offline
            } catch { if !Task.isCancelled { model.report(error); matches = [] } }
            searching = false
        }
        .confirmationDialog("Restore this session?", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }), presenting: restoring) { session in
            Button("Restore session") { Task { _ = await model.attempt { try await model.restoreSession(session.id) } } }
        }
    }

    private func open(_ session: ExpoSession) {
        if session.deletedAt != nil { restoring = session } else { model.selectedSessionID = session.id }
    }

    private func empty(_ title: String, _ body: String, art: String) -> some View {
        EmptyScene(animation: art == "magnifyingglass" ? "sent" : "calendar", title: title, detail: body) { EmptyView() }
    }
}
