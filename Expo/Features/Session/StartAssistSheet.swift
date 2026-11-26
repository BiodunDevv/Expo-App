import SwiftUI
import UniformTypeIdentifiers

/// Shown before every Assist session. Both fields are optional.
struct StartAssistSheet: View {
    @Environment(AppModel.self) private var model
    @State private var title = ""
    @State private var brief = ""
    @State private var remember = false
    @State private var starting = false
    @State private var message = ""
    @FocusState private var titleFocused: Bool

    private var hasSaved: Bool { !model.state.settings.savedBrief.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("About this meeting").font(.system(size: 18, weight: .bold))
                Text("Optional. Tell Expo what this conversation is, and it will keep it in mind when it answers.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Field(label: "Meeting name", text: $title)
                .focused($titleFocused)
            VStack(alignment: .leading, spacing: 5) {
                Text("What should Expo know?").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondary)
                TextEditor(text: $brief)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 150)
                    .background(Theme.surface, in: .rect(cornerRadius: 9))
                    .overlay { RoundedRectangle(cornerRadius: 9).stroke(Theme.border) }
                    .accessibilityLabel("Meeting brief")
                    .onChange(of: brief) {
                        if brief.count > MeetingBrief.maxCharacters { brief = String(brief.prefix(MeetingBrief.maxCharacters)) }
                    }
                Text("The kind of meeting, who is in it, your goals, or paste the job description. Expo uses it only when it helps an answer.")
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Toggle(hasSaved ? "Save this as my new default" : "Remember for next time", isOn: $remember)
                    .toggleStyle(.checkbox).font(.system(size: 12))
                if hasSaved {
                    Button("Clear saved") {
                        model.updateSettings { $0.savedBrief = "" }
                        brief = ""
                    }
                    .buttonStyle(.expo(.plain, compact: true))
                }
            }
            if let blocker = model.readiness.blockers.first {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.warning)
                    Text("\(blocker.title): \(blocker.detail)").font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Ready check") { model.presentingStart = false; model.open(.home) }.buttonStyle(.expo(.plain, compact: true))
                }
                .padding(9)
                .background(Theme.warningSoft, in: .rect(cornerRadius: 9))
            }
            if !message.isEmpty { Text(message).font(.system(size: 12)).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("Cancel") { model.presentingStart = false }
                    .buttonStyle(.expo(.secondary)).keyboardShortcut(.cancelAction).disabled(starting)
                Button(starting ? "Starting…" : "Start", action: start)
                    .buttonStyle(.expo).keyboardShortcut(.return, modifiers: .command).disabled(starting)
            }
        }
        .padding(22)
        .frame(width: 480)
        .background(Theme.background)
        .interactiveDismissDisabled(starting)
        .onAppear { brief = model.state.settings.savedBrief; titleFocused = true }
    }

    private func start() {
        starting = true
        message = ""
        Task {
            do { try await model.startAssist(title: title, brief: brief, remember: remember) }
            catch { message = userMessage(error, fallback: "Expo couldn't start listening. Check your audio settings and try again.") }
            starting = false
        }
    }
}
