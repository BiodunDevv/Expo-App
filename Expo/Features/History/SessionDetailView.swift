import SwiftUI

struct SessionDetailView: View {
    @Environment(AppModel.self) private var model
    var sessionID: String
    @State private var title = ""
    @State private var loading = true
    @State private var loadError: String?
    @State private var confirmDelete = false
    @State private var confirmNotes = false

    var body: some View {
        if let session = model.store.session(sessionID) {
            Page(title: session.title, subtitle: "\(ISO.display(session.startedAt)) · \(clock(session.durationSeconds))") {
                HStack {
                    Button { model.selectedSessionID = nil } label: { Label("History", systemImage: "chevron.left") }.buttonStyle(.expo(.secondary, compact: true))
                    Spacer()
                    Button("Delete session") { confirmDelete = true }.buttonStyle(.expo(.plain, compact: true))
                }
                HStack(alignment: .bottom) {
                    Field(label: "Session title", text: $title)
                    AsyncButton(title: "Save", kind: .secondary) { _ = await model.attempt { try await model.saveSession(sessionID, title: title.trimmed) } }
                        .disabled(title.trimmed.isEmpty || title.trimmed == session.title)
                }
                if loading { HStack { ProgressView().controlSize(.small); Text("Fetching the confirmed transcript and notes.") } }
                if let loadError {
                    Card { Text(loadError).foregroundStyle(Theme.danger); AsyncButton(title: "Try again", kind: .secondary) { await load() } }
                }
                notes(session)
                if !session.assistantMessages.isEmpty {
                    Card(title: "Expo", icon: "bot") {
                        ForEach(session.assistantMessages) { message in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Question: \(message.question)").font(.system(size: 12, weight: .semibold))
                                MarkdownText(text: message.summary)
                                if let suggested = message.suggestedResponse { MarkdownText(text: suggested) }
                            }
                            .padding(.bottom, 6)
                        }
                    }
                }
                Card(title: "Transcript", icon: "mic") {
                    if session.transcriptCursor != nil {
                        AsyncButton(title: "Load earlier", kind: .secondary, compact: true) { _ = await model.attempt { try await model.loadEarlierTranscript(sessionID) } }
                    }
                    if session.transcript.isEmpty { Text("No transcript was captured.").font(.system(size: 12)).foregroundStyle(Theme.secondary) }
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(session.transcript) { TranscriptRow(segment: $0) }
                    }
                }
            }
            .task { title = session.title; await load() }
            .confirmationDialog("Move this session to deleted history?", isPresented: $confirmDelete) {
                Button("Delete session", role: .destructive) {
                    Task {
                        if await model.attempt({ try await model.deleteSession(sessionID) }) { model.selectedSessionID = nil }
                    }
                }
            } message: {
                Text("The transcript and notes can be restored from History. Nothing is permanently deleted.")
            }
        }
    }

    private func load() async {
        loading = true
        loadError = nil
        // A running or syncing session is refreshed by Assist itself.
        if model.store.session(sessionID)?.status != "processing" {
            do { try await model.loadSession(sessionID) } catch { loadError = error.localizedDescription }
        }
        title = model.store.session(sessionID)?.title ?? title
        loading = false
    }

    @ViewBuilder private func notes(_ session: ExpoSession) -> some View {
        if let notes = session.notes {
            Card(title: "Overview", icon: "star") {
                MarkdownText(text: notes.overview)
                list("Key points", notes.keyPoints)
                list("Key decisions", notes.decisions)
                if !notes.actions.isEmpty {
                    Text("Action items").font(.system(size: 12, weight: .semibold))
                    ForEach(notes.actions) { action in
                        Toggle(isOn: Binding(get: { action.done }, set: { done in
                            var updated = notes
                            if let index = updated.actions.firstIndex(where: { $0.id == action.id }) { updated.actions[index].done = done }
                            Task { _ = await model.attempt { try await model.saveSession(sessionID, notes: updated) } }
                        })) {
                            VStack(alignment: .leading) {
                                Text(action.text).font(.system(size: 12))
                                Text([action.owner, action.due].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                list("Open questions", notes.openQuestions)
                if !notes.followUp.isEmpty {
                    Text("Suggested follow-up").font(.system(size: 12, weight: .semibold))
                    MarkdownText(text: notes.followUp)
                }
                Button("Copy notes") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(plain(session.title, notes), forType: .string)
                    model.notify("Notes copied.")
                }
                .buttonStyle(.expo(.secondary, compact: true))
                // The current notes stay until the new version is ready.
                if session.notesStatus == "pending" {
                    HStack { ProgressView().controlSize(.small); Text("Preparing new notes…").font(.system(size: 12)) }
                } else {
                    if session.notesStatus == "failed", let error = session.notesError {
                        Text(error).font(.system(size: 12)).foregroundStyle(Theme.danger)
                    }
                    Button(session.notesStatus == "failed" ? "Try again" : "Generate new notes") { confirmNotes = true }
                        .buttonStyle(.expo(.secondary, compact: true))
                }
            }
            .confirmationDialog("Generate new session notes?", isPresented: $confirmNotes) {
                Button("Generate notes") { Task { _ = await model.attempt { try await model.generateNotes(sessionID) } } }
            } message: {
                Text("Expo will create a new version from the confirmed transcript. Your current notes remain until it is ready.")
            }
        } else {
            Card(title: "Notes", icon: "resume") {
                if session.notesStatus == "pending" {
                    HStack { ProgressView().controlSize(.small); Text("Preparing your notes…").font(.system(size: 12)) }
                } else {
                    if let error = session.notesError { Text(error).font(.system(size: 12)).foregroundStyle(Theme.danger) }
                    AsyncButton(title: "Generate notes", busyTitle: "Generating…") { _ = await model.attempt { try await model.generateNotes(sessionID) } }
                }
            }
        }
    }

    @ViewBuilder private func list(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            Text(title).font(.system(size: 12, weight: .semibold))
            MarkdownText(text: items.map { "- \($0)" }.joined(separator: "\n"))
        }
    }

    private func plain(_ title: String, _ notes: SessionNotes) -> String {
        func section(_ name: String, _ items: [String]) -> String {
            items.isEmpty ? "" : "\n\n\(name)\n" + items.map { "- \($0)" }.joined(separator: "\n")
        }
        return title + "\n\n" + notes.overview + section("Key points", notes.keyPoints) + section("Decisions", notes.decisions)
            + section("Action items", notes.actions.map(\.text)) + section("Open questions", notes.openQuestions)
            + (notes.followUp.isEmpty ? "" : "\n\nFollow-up\n\(notes.followUp)")
    }
}

struct TranscriptRow: View {
    var segment: TranscriptSegment

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(segment.at).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.tertiary)
            Text(segment.speaker).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(segment.speaker == "You" ? Theme.accent : Theme.secondary).frame(width: 56, alignment: .leading)
            Text(segment.text).font(.system(size: 12.5)).textSelection(.enabled)
                .foregroundStyle(segment.confidence == "low" ? Theme.secondary : Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
