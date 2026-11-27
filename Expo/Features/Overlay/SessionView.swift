import BorderBeamKit
import SwiftUI

/// The session window: one sheet of glass with the input on top, the chat
/// under it when open, and the tools along the bottom. Made small, it is only a
/// note that a meeting is going on.
struct SessionView: View {
    @Environment(AppModel.self) private var model
    let overlays: OverlayController
    @State private var composer = Composer()
    @State private var showingOptions = false
    /// Whether the answers were closed before the options opened them.
    @State private var closedBeforeOptions = false

    private static let radius: CGFloat = 18
    private var assist: AssistController { model.assist }

    var body: some View {
        Group {
            if model.layout.compact { CompactSession(overlays: overlays) }
            else { full }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Theme.text)
        .onChange(of: model.layout) { old, new in
            if !new.chatOpen || new.compact { showingOptions = false; closedBeforeOptions = false }
            // Something asked for shows its reply, not the options.
            if new.jumps != old.jumps { closedBeforeOptions = false; showingOptions = false }
            if new.compact != old.compact || new.chatOpen != old.chatOpen { overlays.fitSession() }
        }
        // Options need room, so they open the window and close it again after.
        .onChange(of: showingOptions) { _, shown in
            if shown {
                closedBeforeOptions = !model.layout.chatOpen
                model.layout.makeRoom(true)
            } else if closedBeforeOptions {
                closedBeforeOptions = false
                model.layout.makeRoom(false)
            }
        }
        // A question being answered shows itself, unless the chat was put away.
        .onChange(of: assist.pendingQuestion) { _, pending in
            guard pending != nil else { return }
            model.showingTranscript = false
            if !showingOptions { model.layout.answerArrived() }
        }
        .onChange(of: assist.currentSession?.liveSuggestions.count) { old, new in
            guard (new ?? 0) > (old ?? 0) else { return }
            model.showingTranscript = false
            if !showingOptions { model.layout.answerArrived() }
        }
        // Re-check the allowance as answers arrive.
        .task(id: assist.currentSession?.assistantMessages.count) { await model.refreshBilling() }
        .task { composer.attach(model) ; await composer.loadSources() }
        // The question appears in the box as it is said, unless the person is typing.
        .onChange(of: assist.liveQuestion, initial: true) { _, live in composer.hear(live, model: model) }
        // The shortcut captures at once.
        .onReceive(NotificationCenter.default.publisher(for: .expoScreenAsk)) { _ in
            if !composer.capturing { composer.setCapturing(true) }
            composer.capture()
        }
        // Escape steps down: options, then the chat, then the small size.
        .onExitCommand {
            if showingOptions { showingOptions = false }
            else if model.layout.compact { overlays.hideAssistant() }
            else if model.layout.chatOpen { model.layout.hideChat() }
            else { model.minimizeSession() }
        }
    }

    /// The input and tools, with the chat between them when it is open.
    private var full: some View {
        let open = model.layout.chatOpen
        // The beam runs round the window only while Expo is hearing or answering.
        return BorderBeam(size: .md, colorVariant: .colorful, theme: .dark,
                          active: !composer.filled.isEmpty || assist.isAsking, borderRadius: Self.radius) {
            VStack(spacing: 0) {
                InputRow(composer: composer)
                    .background(Color.white.opacity(0.1))
                SessionNotices(composer: composer)
                if open {
                    Divider().overlay(Glass.line)
                    Group {
                        if showingOptions { SessionOptions { showingOptions = false } }
                        else { SessionBody() }
                    }
                    .frame(maxHeight: .infinity)
                }
                Divider().overlay(Glass.line)
                SessionToolbar(composer: composer, overlays: overlays, showingOptions: $showingOptions)
                    .movesWindow(overlays, .session)
            }
            .fixedSize(horizontal: false, vertical: !open)
            .glassCard(radius: Self.radius)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if !model.layout.chatOpen { overlays.setClosedHeight(height) }
            }
        }
        .overlay { ResizeEdges(overlays: overlays) }
        // While the window is growing, the content is revealed, not squeezed.
        .frame(minWidth: SessionFrame.minimumWidth)
    }
}
