import SwiftUI
import ThinkingOrbsKit

struct AssistantPanelView: View {
    @Environment(AppModel.self) private var model
    let overlays: OverlayController
    @State private var question = ""
    @State private var showTranscript = true
    @State private var sources: [ScreenSource] = []
    @State private var sourceID: String?
    @State private var attachScreen = false
    /// The text Expo put in the box from what it heard.
    @State private var filled = ""
    @State private var atEnd = true
    @FocusState private var focused: Bool

    private var assist: AssistController { model.assist }

    private enum Entry: Identifiable {
        case answer(AssistantMessage), suggestion(LiveSuggestion)
        var id: String {
            switch self { case .answer(let a): a.id; case .suggestion(let s): s.id }
        }
        var date: String {
            switch self { case .answer(let a): a.createdAt ?? ""; case .suggestion(let s): s.createdAt }
        }
    }

    private var entries: [Entry] {
        guard let session = assist.currentSession else { return [] }
        // Only suggestions the person asked for. Unasked ones answered every
        // sentence, so Expo now answers recognised questions instead.
        let suggestions = session.liveSuggestions.filter { $0.status != "superseded" && $0.trigger != "automatic" }
        return (session.assistantMessages.map(Entry.answer) + suggestions.map(Entry.suggestion)).sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.glanceMode {
                GlanceCard(answer: latest, streaming: assist.pendingQuestion != nil) { setGlance(false) }
            } else {
                AnswerModeBar()
                Divider()
                // Without auto answers the transcript is the main thing, until a question is asked.
                if !assist.autoAnswer && entries.isEmpty && assist.pendingQuestion == nil {
                    LiveTranscript(expanded: true)
                } else {
                    if showTranscript && !model.panelCompact { LiveTranscript(expanded: false); Divider() }
                    conversation
                }
            }
            if model.billing?.answersUsedUp == true {
                Text("Smart answers paused: your monthly answers are used up.")
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.warning)
                    .frame(maxWidth: .infinity).padding(7).background(Theme.warningSoft)
            }
            if model.glanceMode { Divider(); composer(compact: true) } else { composer(compact: false) }
        }
        .foregroundStyle(Theme.text)
        .background(Theme.surface)
        .clipShape(.rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(Theme.border) }
        .overlay(alignment: .top) { ToastStack().padding(.top, 40) }
        .onAppear { focused = true }
        .task { await loadSources() }
        .onChange(of: attachScreen) { _, on in if on { Task { await loadSources(prompt: true) } } }
        // Re-check the allowance as answers arrive.
        .task(id: entries.count) { await model.refreshBilling() }
        .onReceive(NotificationCenter.default.publisher(for: .expoFocusAsk)) { _ in focused = true }
        .onReceive(NotificationCenter.default.publisher(for: .expoScreenAsk)) { _ in send(withScreen: true) }
        .onExitCommand { overlays.hideAssistant() }
    }

    /// The streaming answer, otherwise the newest finished answer or suggestion.
    private var latest: String? {
        if assist.pendingQuestion != nil { return assist.streamedText }
        for entry in entries.reversed() {
            switch entry {
            case .answer(let message): return message.summary
            case .suggestion(let suggestion):
                if !suggestion.text.isEmpty && suggestion.status != "failed" { return suggestion.text }
            }
        }
        return nil
    }

    private func setGlance(_ on: Bool) {
        model.glanceMode = on
        overlays.fitAssistant()
        focused = true
    }

    /// Uses the full labels when they fit and compact controls when they do not.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            headerRow(compact: false)
            headerRow(compact: true)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .movesWindow(overlays, .assistant)
        .help("Drag to move")
    }

    private func headerRow(compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 10) {
            Logo(size: 24)
            if !model.glanceMode && !compact {
                Text(statusTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1).fixedSize()
            } else if assist.snapshot.connection != .connected || assist.snapshot.lifecycle == .paused {
                Text(statusTitle).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.warning).lineLimit(1)
            }
            PrivacyToggle()
            Spacer(minLength: 0)
            if !model.glanceMode {
                icon("text.alignleft", showTranscript ? "Hide transcript" : "Show transcript") { showTranscript.toggle() }
                Button { overlays.toggleAssistantSize() } label: {
                    Label(model.panelCompact ? "Expand" : "Shrink",
                          systemImage: model.panelCompact ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                }
                .buttonStyle(ChipStyle())
            }
            icon(model.glanceMode ? "list.bullet.rectangle" : "rectangle.compress.vertical",
                 model.glanceMode ? "Show conversation" : "Glance view") { setGlance(!model.glanceMode) }
            icon("xmark", "Close") { overlays.hideAssistant() }
        }
    }

    private var statusTitle: String {
        if assist.snapshot.connection == .reconnecting { return "Reconnecting…" }
        if assist.snapshot.connection == .offline { return "Offline" }
        return assist.snapshot.lifecycle == .paused ? "Paused" : assist.isPractice ? "Practice session" : "Live assistance"
    }

    private func icon(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 24, height: 24).contentShape(.rect) }
            .buttonStyle(.plain).foregroundStyle(Theme.secondary).help(label).accessibilityLabel(label)
    }

    /// A new answer is shown from its first line, then left alone while it streams.
    private var conversation: some View {
        ScrollViewReader { scroll in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if entries.isEmpty && assist.pendingQuestion == nil { ChatEmptyState() }
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 16) {
                        switch entry {
                        case .answer(let message):
                            QuestionBubble(text: message.question, screen: message.screenContextUsed == true, time: time(message.createdAt))
                            ExpoMessage {
                                MarkdownText(text: message.summary)
                                AnswerActions(text: message.summary)
                            }
                        case .suggestion(let suggestion):
                            ExpoMessage(tag: "Suggestion", time: time(suggestion.createdAt)) {
                                if suggestion.status == "failed" {
                                    Text(suggestion.errorMessage ?? "This suggestion could not be completed.").font(.system(size: 12)).foregroundStyle(Theme.danger)
                                    AsyncButton(title: "Retry", kind: .secondary, compact: true) { await assist.retrySuggestion(suggestion.id) }
                                } else if suggestion.text.isEmpty {
                                    ThinkingLabel(text: "Writing a suggestion", state: .composing)
                                } else {
                                    MarkdownText(text: suggestion.text)
                                    AnswerActions(text: suggestion.text)
                                }
                            }
                        }
                    }
                    .id(entry.id)
                }
                if let pending = assist.pendingQuestion {
                    VStack(alignment: .leading, spacing: 16) {
                        QuestionBubble(text: pending, screen: false, time: nil)
                        ExpoMessage(live: true) {
                            if assist.streamedText.isEmpty { ThinkingLabel() }
                            else {
                                MarkdownText(text: assist.streamedText)
                                ThinkingLabel(text: "Writing", state: .composing)
                            }
                        }
                    }
                    .id("pending")
                    // Room to bring the new question to the top.
                    Color.clear.frame(height: 200)
                }
                // Seen only when the newest message is in view.
                Color.clear.frame(height: 1).id("end")
                    .onAppear { atEnd = true }
                    .onDisappear { atEnd = false }
            }
            .padding(14)
        }
        .frame(maxHeight: .infinity)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            if !atEnd && !entries.isEmpty && assist.pendingQuestion == nil {
                Button { withAnimation(.snappy) { scroll.scrollTo("end", anchor: .bottom) } } label: {
                    Label("Latest", systemImage: "arrow.down")
                }
                .buttonStyle(ChipStyle(on: true))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: atEnd)
        .onAppear { if let last = entries.last?.id { scroll.scrollTo(last, anchor: .top) } }
        .onChange(of: assist.pendingQuestion) { _, pending in
            if pending != nil { scroll.scrollTo("pending", anchor: .top) }
        }
        .onChange(of: entries.map(\.id)) { old, new in
            // A streamed answer was aligned when it began; only whole suggestions move the view.
            guard let added = entries.last(where: { !old.contains($0.id) }), case .suggestion = added else { return }
            scroll.scrollTo(added.id, anchor: .top)
        }
        }
    }

    private func time(_ iso: String?) -> String? {
        guard let iso else { return nil }
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return (precise.date(from: iso) ?? ISO8601DateFormatter().date(from: iso))?.formatted(date: .omitted, time: .shortened)
    }

    private var microphoneOn: Bool {
        assist.snapshot.lifecycle == .listening ? assist.capturingMicrophone : model.state.settings.captureMicrophone
    }

    /// One rounded field with its tools inside, and Send or Stop at the end.
    private func composer(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            if !compact && !entries.isEmpty {
                HStack(spacing: 6) {
                    Button { Task { await assist.suggest() } } label: { Label("What should I say?", systemImage: "sparkles") }
                    Button("Summarize") { assist.submit("Summarize the conversation so far.", label: "Summarize") }
                    Button("Explain this") { assist.submit("Explain this") }
                }
                .buttonStyle(ChipStyle())
                .disabled(assist.isAsking)
            }
            VStack(alignment: .leading, spacing: 8) {
                if !filled.isEmpty {
                    HStack(spacing: 6) {
                        VoiceOrb(level: assist.level, size: 16)
                        Text("Listening. Sends at the next pause.")
                            .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.secondary)
                        Spacer(minLength: 4)
                        Button("Clear") { filled = ""; question = ""; assist.forgetHeard() }.buttonStyle(ChipStyle())
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                TextField(attachScreen ? "Ask about your screen…" : "Ask Expo…", text: $question, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 13)).lineLimit(1...4)
                    .focused($focused)
                    .onSubmit { send(withScreen: attachScreen) }
                    .accessibilityLabel("Question")
                HStack(spacing: 6) {
                    Button { attachScreen.toggle() } label: { Label("Screen", systemImage: "rectangle.on.rectangle") }
                        .buttonStyle(ChipStyle(on: attachScreen))
                        .help("Include your screen with this question (⇧⌘↩)")
                    if attachScreen {
                        Menu {
                            ForEach(sources) { source in Button(source.name) { sourceID = source.id } }
                            Divider()
                            Button("Refresh sources") { Task { await loadSources(prompt: true) } }
                        } label: {
                            Text(sources.first { $0.id == sourceID }?.name ?? "Main screen").lineLimit(1)
                        }
                        .menuStyle(.borderlessButton).font(.system(size: 11)).frame(maxWidth: 150)
                    }
                    Spacer(minLength: 4)
                    HStack(spacing: 5) {
                        if assist.snapshot.lifecycle == .listening { VoiceOrb(level: assist.level, size: 20) }
                        else { Image(systemName: "waveform") }
                        Image(systemName: microphoneOn ? "mic.fill" : "mic.slash")
                    }
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    .help(microphoneOn ? "Microphone on" : "Microphone off")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(microphoneOn ? "Microphone enabled" : "Microphone disabled")
                    Button {
                        if assist.isAsking { assist.stopAnswer() } else { send(withScreen: attachScreen) }
                    } label: {
                        Image(systemName: assist.isAsking ? "stop.fill" : "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                            .frame(width: 28, height: 28)
                            .background(Theme.accent, in: .circle)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .disabled(!assist.isAsking && question.trimmed.isEmpty)
                    .opacity(!assist.isAsking && question.trimmed.isEmpty ? 0.35 : 1)
                    .accessibilityLabel(assist.isAsking ? "Stop answering" : "Send")
                }
            }
            .padding(.horizontal, 12).padding(.top, 11).padding(.bottom, 8)
            .background(Theme.background, in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(focused ? Theme.tertiary : Theme.border) }
        }
        .padding(10)
        .animation(.snappy(duration: 0.2), value: filled.isEmpty)
        // The question appears in the box as it is said, unless the person is typing.
        .onChange(of: assist.liveQuestion, initial: true) { _, live in
            guard question.isEmpty || question == filled else { return }
            filled = live
            question = live
        }
        .onChange(of: question) { _, typed in
            guard !filled.isEmpty, typed != filled else { return }
            // Editing takes the question over, so it is not also sent by itself.
            filled = ""
            assist.forgetHeard()
        }
    }

    /// Screen permission is only requested once the user opts into screen questions.
    private func loadSources(prompt: Bool = false) async {
        guard prompt || CGPreflightScreenCaptureAccess() else { return }
        do { sources = try await ScreenContextCapture.sources() }
        catch { sources = []; if prompt { model.report(error) } }
        if !sources.contains(where: { $0.id == sourceID }) { sourceID = nil }
    }

    private func send(withScreen: Bool) {
        let text = question
        guard !assist.isAsking else { return }
        if !filled.isEmpty { assist.forgetHeard() }
        if !text.trimmed.isEmpty { filled = ""; question = ""; attachScreen = false }
        assist.submit(text, withScreen: withScreen, sourceID: sourceID)
    }
}
