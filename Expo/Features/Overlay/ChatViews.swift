import SwiftUI
import ThinkingOrbsKit

// The pieces of the conversation: messages, the waiting state, the empty state
// and the composer's controls.

/// What the person asked, on the right.
struct QuestionBubble: View {
    var text: String
    var screen: Bool
    var time: String?

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if screen { Image(systemName: "rectangle.on.rectangle").accessibilityLabel("Asked with your screen") }
                    Text(text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(Theme.accent, in: .rect(topLeadingRadius: 15, bottomLeadingRadius: 15, bottomTrailingRadius: 5, topTrailingRadius: 15))
                if let time { Text(time).font(.system(size: 10)).foregroundStyle(Theme.tertiary) }
            }
        }
    }
}

/// An answer from Expo: who, when, the text, then what can be done with it.
struct ExpoMessage<Content: View>: View {
    var tag: String?
    var time: String?
    /// The newest message, still being written, has a moving bot.
    var live = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Group {
                if live { RobotMark(size: 24) } else { Logo(size: 24) }
            }
            .padding(.top, -1)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text("Expo").font(.system(size: 11.5, weight: .bold))
                    if let tag { Tag(text: tag, tone: .accent) }
                    if let time { Text(time).font(.system(size: 10.5)).foregroundStyle(Theme.tertiary) }
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Copy, and ask for the answer in another form.
struct AnswerActions: View {
    @Environment(AppModel.self) private var model
    var text: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 4) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
                Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
            } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") }
            ForEach(Refinement.allCases) { refinement in
                Button(refinement.rawValue) {
                    model.assist.submit(refinement.prompt(for: text), label: "\(refinement.rawValue) version")
                }
                .disabled(model.assist.isAsking)
            }
        }
        .buttonStyle(ChipStyle())
    }
}

/// A quiet pill button.
struct ChipStyle: ButtonStyle {
    var on = false
    func makeBody(configuration: Configuration) -> some View { Chip(configuration: configuration, on: on) }

    private struct Chip: View {
        let configuration: ButtonStyle.Configuration
        let on: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(on ? Theme.onAccent : hovering ? Theme.text : Theme.secondary)
                .padding(.horizontal, 9).frame(height: 24)
                .background(on ? Theme.accent : hovering ? Theme.selected : Theme.subtle, in: .capsule)
                .contentShape(.capsule)
                .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
                .fixedSize()
                .onHover { hovering = $0 }
        }
    }
}

/// A thinking orb beside what Expo is doing.
struct ThinkingLabel: View {
    var text = "Thinking"
    var state = OrbState.searching

    var body: some View {
        HStack(spacing: 8) {
            ThinkingOrb(state: state, size: .px20)
            Text("\(text)…").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// Before the first question: the listening orb and ways to begin.
struct ChatEmptyState: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let listening = model.assist.snapshot.lifecycle == .listening
        VStack(spacing: 14) {
            if !model.panelCompact { VoiceOrb(level: model.assist.level, size: 68, active: listening) }
            VStack(spacing: 4) {
                Text(listening ? "I’m listening" : "Ready when you are").font(.system(size: 15, weight: .bold))
                Text(model.assist.isPractice ? "Ask or play a practice question. A model answer appears here."
                     : model.assist.autoAnswer ? "Speak, and Expo answers at each pause. You can also type below." : "Ask about this conversation, or let Expo suggest what to say.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
            }
            VStack(spacing: 7) {
                starter("star", "What should I say?") { Task { await model.assist.suggest() } }
                starter("resume", "Summarize so far") { model.assist.submit("Summarize the conversation so far.", label: "Summarize so far") }
                starter("chat", "Explain the last point") { model.assist.submit("Explain the last point made in this conversation.", label: "Explain the last point") }
            }
            .frame(maxWidth: 300)
            .disabled(model.assist.isAsking)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func starter(_ symbol: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Icon8(symbol, size: 24)
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(Theme.tertiary)
            }
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 12).frame(height: 42)
            .background(Theme.surface, in: .rect(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).stroke(Theme.border) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
