import SwiftUI

/// Ways to ask, and how answers and the window look. Shown inside the window, so
/// every choice is in view and nothing hides behind a submenu.
struct SessionOptions: View {
    @Environment(AppModel.self) private var model
    var close: () -> Void

    private var assist: AssistController { model.assist }

    var body: some View {
        let settings = model.state.settings
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Options").font(.system(size: 13.5, weight: .bold))
                    Spacer()
                    Button("Done", action: close).buttonStyle(ChipStyle(on: true))
                }
                section("Ask") {
                    FlowRow {
                        ask("What should I say?", "sparkles") { Task { await assist.suggest() } }
                        ask("Summarize so far", "text.alignleft") { assist.submit("Summarize the conversation so far.", label: "Summarize so far") }
                        ask("Explain the last point", "lightbulb") { assist.submit("Explain the last point made in this conversation.", label: "Explain the last point") }
                    }
                }
                section("Answer style", note: settings.answerStyle.detail) {
                    ChoiceBar(options: AnswerStyle.allCases, title: \.title, selection: setting(\.answerStyle))
                }
                section("See-through", note: "How much of the screen shows through this window.") {
                    ChoiceBar(options: SeeThrough.allCases, title: \.title, selection: setting(\.seeThrough))
                }
                VStack(spacing: 12) {
                    toggle("Simple English", "Everyday words and short sentences.", setting(\.plainEnglish))
                    if assist.autoAnswer && !assist.isPractice {
                        toggle("Include my voice", "Answer what your microphone hears too.", setting(\.answerOwnQuestions))
                    }
                    if model.canEmailNotes, let session = assist.currentSession {
                        toggle("Email me the transcript", "Notes and transcript, sent when this session ends.", Binding(
                            get: { session.emailNotes ?? settings.emailNotes },
                            set: { model.setEmailNotes($0, for: session.id) }))
                    }
                    toggle("Glance view", "Show only a headline and key points.", Binding(
                        get: { model.glanceMode }, set: { model.glanceMode = $0 }))
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .textHalo()
        }
        .scrollBounceBehavior(.basedOnSize)
        // Choices read plainly whatever shows through the rest of the window.
        .background(Glass.base.opacity(0.72))
    }

    private func section(_ title: String, note: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11.5, weight: .bold)).foregroundStyle(Theme.secondary)
            content()
            if let note { Text(note).font(.system(size: 11)).foregroundStyle(Theme.tertiary).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private func ask(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button {
            close()
            model.layout.asked()
            action()
        } label: { Label(title, systemImage: symbol) }
            .buttonStyle(ChipStyle())
            .disabled(assist.isAsking)
    }

    private func toggle(_ title: String, _ detail: String, _ value: Binding<Bool>) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12.5, weight: .semibold))
                    Text(detail).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 8)
                // Drawn by hand: system switches look off in a window that is not in focus.
                Capsule().fill(value.wrappedValue ? Color.white.opacity(0.92) : Color.white.opacity(0.18))
                    .frame(width: 34, height: 20)
                    .overlay(alignment: value.wrappedValue ? .trailing : .leading) {
                        Circle().fill(value.wrappedValue ? Glass.base : Color.white).frame(width: 16, height: 16).padding(2)
                    }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: value.wrappedValue)
        .accessibilityElement(children: .combine)
        .accessibilityValue(value.wrappedValue ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }

    private func setting<T>(_ path: WritableKeyPath<ExpoSettings, T>) -> Binding<T> {
        Binding(get: { model.state.settings[keyPath: path] }, set: { value in model.updateSettings { $0[keyPath: path] = value } })
    }
}

/// Equal segments with a liquid selection.
struct ChoiceBar<Value: Hashable & Identifiable>: View {
    var options: [Value]
    var title: (Value) -> String
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let chosen = option == selection
                Button { selection = option } label: {
                    Text(title(option)).font(.system(size: 11.5, weight: chosen ? .bold : .medium)).lineLimit(1)
                        .frame(maxWidth: .infinity).frame(height: 28).contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .foregroundStyle(chosen ? Theme.text : Theme.secondary)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .background { GooeyPill(index: options.firstIndex(of: selection) ?? 0, count: options.count, fill: Glass.selected) }
        .padding(3)
        .background(Glass.fill, in: .capsule)
        .frame(maxWidth: 460)
    }
}

/// Lays its views out in a line, wrapping to the next when they do not fit.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, point) in zip(subviews, arrange(subviews, width: bounds.width).points) {
            view.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += line + spacing; line = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + line), points)
    }
}
