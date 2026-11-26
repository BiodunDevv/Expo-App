import SwiftUI

// What the person sees while Expo listens: how it should respond, and the
// transcript being saved.

/// Answer as questions are asked, or only keep the transcript.
struct AnswerModeBar: View {
    @Environment(AppModel.self) private var model
    @Namespace private var highlight

    var body: some View {
        let assist = model.assist!
        let locked = model.billing?.smartAnswersLocked == true
        let auto = assist.autoAnswer && !locked
        VStack(spacing: 7) {
            HStack(spacing: 3) {
                option("bot", "Auto answer", selected: auto) { Task { await assist.setAutoAnswer(true) } }
                    .disabled(locked)
                option("resume", "Transcript only", selected: !auto) { Task { await assist.setAutoAnswer(false) } }
            }
            .padding(3)
            .background(Theme.subtle, in: .rect(cornerRadius: 13))
            HStack(spacing: 8) {
                Text(locked ? "Auto answers are not included in your plan. Your transcript is still saved."
                     : auto ? "Everything heard is sent to Expo at each pause." : "Saving the transcript. Ask whenever you like.")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if auto && !assist.isPractice {
                    Toggle("Include my voice", isOn: Binding(
                        get: { model.state.settings.answerOwnQuestions },
                        set: { value in model.updateSettings { $0.answerOwnQuestions = value } }))
                        .toggleStyle(.checkbox).font(.system(size: 11))
                        .help("Also send what your own microphone hears")
                        .fixedSize()
                }
            }
            .padding(.horizontal, 3)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Theme.surface)
        .animation(.snappy(duration: 0.25), value: auto)
    }

    private func option(_ icon: String, _ title: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Icon8(icon, size: 20)
                Text(title).font(.system(size: 12.5, weight: selected ? .bold : .medium))
            }
            .frame(maxWidth: .infinity).frame(height: 32)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.surface)
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                        .matchedGeometryEffect(id: "mode", in: highlight)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Theme.text : Theme.secondary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The live transcript. `expanded` gives it the whole panel.
struct LiveTranscript: View {
    @Environment(AppModel.self) private var model
    var expanded: Bool

    var body: some View {
        let session = model.assist.currentSession
        let segments = Array(session?.transcript.suffix(expanded ? 200 : 40) ?? [])
        let preview = model.assist.preview
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Icon8("audio", size: 16)
                Text("Live transcript").font(.system(size: 11.5, weight: .bold))
                Spacer()
                if let count = session?.transcript.count, count > 0 {
                    Label("\(count) line\(count == 1 ? "" : "s") saved", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.success)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 14).padding(.top, 9).padding(.bottom, 5)
            if segments.isEmpty && preview == nil {
                if expanded {
                    EmptyScene(animation: "sent", title: "Listening for the first words",
                               detail: "Everything said is written here and saved to History when you end the session.") { EmptyView() }
                        .frame(maxHeight: .infinity)
                } else {
                    Text("Waiting for conversation audio…").font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(segments) { LiveLine(speaker: $0.speaker, time: $0.at, text: $0.text) }
                        if let preview {
                            LiveLine(speaker: preview.source == "microphone" ? "You" : "…", time: "", text: preview.text, pending: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 9)
                }
                .defaultScrollAnchor(.bottom)
                .clipped()
            }
        }
        .frame(maxHeight: expanded ? .infinity : segments.isEmpty && preview == nil ? 58 : 118)
        .background(Theme.background)
        .animation(.snappy(duration: 0.2), value: segments.count)
    }
}

private struct LiveLine: View {
    var speaker: String
    var time: String
    var text: String
    var pending = false

    var body: some View {
        let mine = speaker == "You"
        HStack(alignment: .top, spacing: 8) {
            Icon8(mine ? "mic" : "audio", size: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(speaker).font(.system(size: 11, weight: .bold))
                    Text(time).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.tertiary)
                }
                Text(text).font(.system(size: 12.5)).italic(pending)
                    .foregroundStyle(pending ? Theme.tertiary : Theme.text)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
        .transition(.opacity.combined(with: .offset(y: 6)))
    }
}
