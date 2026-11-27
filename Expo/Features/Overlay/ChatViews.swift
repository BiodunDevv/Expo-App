import SwiftUI
import ThinkingOrbsKit

// The pieces of the conversation: messages, the waiting state, the empty state
// and the composer's controls.

/// What was asked, on the right, with the captured picture when there is one.
struct QuestionBubble: View {
    var text: String
    var screen: Bool
    /// The capture behind the question, kept only while the session runs.
    var picture: String?
    @State private var showing = false

    private var image: NSImage? {
        guard let encoded = picture?.split(separator: ",", maxSplits: 1).last, let data = Data(base64Encoded: String(encoded)) else { return nil }
        return NSImage(data: data)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack {
                Spacer(minLength: 60)
                Text(text).font(.system(size: 12.5, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color.white.opacity(0.13), in: .rect(cornerRadius: 16))
                    .overlay { RoundedRectangle(cornerRadius: 16).stroke(Glass.line) }
            }
            if picture != nil {
                Button { showing.toggle() } label: { Label(showing ? "Hide screenshot" : "View screenshot", systemImage: "photo") }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                if showing, let image {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(.rect(cornerRadius: 10))
                        .accessibilityLabel("The captured screen")
                }
            } else if screen {
                Label("Asked with your screen", systemImage: "photo").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
        }
        .textHalo()
    }
}

/// Copy, and ask for the answer in another form.
struct AnswerActions: View {
    @Environment(AppModel.self) private var model
    var text: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 2) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
                Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
            } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc").frame(width: 26, height: 24).contentShape(.rect) }
                .buttonStyle(.plain)
                .hint("Copy the answer").accessibilityLabel(copied ? "Copied" : "Copy answer")
            Menu {
                ForEach(Refinement.allCases) { refinement in
                    Button(refinement.rawValue) {
                        model.assist.submit(refinement.prompt(for: text), label: "\(refinement.rawValue) version")
                    }
                }
            } label: { Image(systemName: "ellipsis").frame(width: 26, height: 24).contentShape(.rect) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .disabled(model.assist.isAsking)
                .hint("Shorter, with an example, or simpler").accessibilityLabel("Change the answer")
        }
        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
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
                .background(on ? Theme.accent : hovering ? Theme.selected : Theme.text.opacity(0.08), in: .capsule)
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

/// Before the first question.
struct SessionEmptyState: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let listening = model.assist.snapshot.lifecycle == .listening
        VStack(spacing: 12) {
            AssistantRing(size: 68)
            VStack(spacing: 4) {
                Text(listening ? "I’m listening" : "Ready when you are").font(.system(size: 15, weight: .semibold))
                Text(model.assist.isPractice ? "Ask or play a practice question."
                     : !listening ? "Type a question, or resume listening."
                     : model.assist.autoAnswer ? "Speak, and answers appear here." : "Type a question and the answer appears here.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            .multilineTextAlignment(.center)
            .textHalo()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
