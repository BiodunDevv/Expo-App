import SwiftUI

/// The top of the window: type or watch what is heard, choose auto answer or
/// transcript, and send.
struct InputRow: View {
    @Environment(AppModel.self) private var model
    @Bindable var composer: Composer
    @FocusState private var focused: Bool

    private var assist: AssistController { model.assist }

    var body: some View {
        HStack(spacing: 10) {
            if model.layout.chatOpen {
                SquareButton(symbol: "arrow.left", label: "Hide chat") { model.layout.hideChat() }
            }
            TextField(placeholder, text: $composer.question, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 14.5)).lineLimit(1...4)
                .focused($focused)
                .onSubmit { composer.send() }
                .accessibilityLabel("Question")
            if !composer.filled.isEmpty {
                Button { composer.dropHeard() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Theme.secondary)
                    .hint("Heard words send at the next pause. Click to drop them.")
                    .accessibilityLabel("Clear heard words")
            }
            modes
            primary
        }
        .padding(.leading, 14).padding(.trailing, 12).padding(.vertical, 11)
        .onAppear { focused = true }
        .onReceive(NotificationCenter.default.publisher(for: .expoFocusAsk)) { _ in focused = true }
    }

    private var placeholder: String {
        if composer.capturing { return "Ask anything about your screen" }
        return model.visibleAnswers.isEmpty ? "Ask anything" : "Ask follow-up"
    }

    private var modes: some View {
        let locked = model.billing?.smartAnswersLocked == true
        let auto = assist.autoAnswer && !locked
        return HStack(spacing: 0) {
            mode("Auto", selected: auto, help: "Auto answer: everything heard is answered at each pause") {
                Task { await assist.setAutoAnswer(true) }
            }
            .disabled(locked)
            mode("Transcript", selected: !auto,
                 help: locked ? "Auto answers are not included in your plan" : "Transcript only: save what is said, and ask when you like") {
                Task { await assist.setAutoAnswer(false) }
            }
        }
        .background { GooeyPill(index: auto ? 0 : 1, count: 2, fill: Glass.selected) }
        .padding(3)
        .background(Glass.fill, in: .capsule)
        .fixedSize()
    }

    private func mode(_ title: String, selected: Bool, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11.5, weight: selected ? .bold : .medium))
                .frame(width: 76, height: 24).contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Theme.text : Theme.secondary)
        .hint(help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Return, stop or capture, whichever applies.
    @ViewBuilder private var primary: some View {
        if assist.isAsking {
            SquareButton(symbol: "stop.fill", label: "Stop answering") { assist.stopAnswer() }
        } else if composer.capturing && composer.typed.isEmpty {
            Button { composer.capture() } label: {
                Label("Capture", systemImage: "return")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(Theme.accent, in: .rect(cornerRadius: 10))
                    .contentShape(.rect)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .hint("Capture your screen and answer it")
            .accessibilityLabel("Capture and answer")
        } else {
            SquareButton(symbol: "return", label: "Send") { composer.send() }
                .disabled(composer.question.trimmed.isEmpty)
        }
    }
}

/// The small rounded square used for the window's buttons.
struct SquareButton: View {
    var symbol: String
    var label: String
    var action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.12), in: .rect(cornerRadius: 10))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.5)
        .hint(label)
        .accessibilityLabel(label)
    }
}
