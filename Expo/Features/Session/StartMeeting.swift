import SwiftUI

/// The one question asked before a meeting starts. Nothing to fill in: Expo
/// names the meeting itself when it ends.
struct StartMeetingConfirmation: View {
    @Environment(AppModel.self) private var model
    /// Closes the question without starting.
    var cancel: () -> Void
    var started: () -> Void = {}
    @State private var starting = false
    @State private var message = ""

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 5) {
                Text("Start a meeting?").font(.system(size: 17, weight: .bold))
                Text("Are you sure you want to start a meeting? Expo listens, helps as you go, and names it when it ends.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            if let profile = model.meetingProfile {
                Label("Using your “\(profile.name)” notes", systemImage: "doc.text")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            if !message.isEmpty {
                Text(message).font(.system(size: 11.5)).foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            } else if let blocker = model.readiness.blockers.first {
                Label("\(blocker.title): \(blocker.detail)", systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 11)).foregroundStyle(Theme.warning)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button("Cancel", action: cancel)
                    .buttonStyle(.expo(.secondary)).keyboardShortcut(.cancelAction).disabled(starting)
                Button(starting ? "Starting…" : "Start meeting", action: start)
                    .buttonStyle(.expo).keyboardShortcut(.defaultAction).disabled(starting)
            }
            .padding(.top, 2)
        }
    }

    private func start() {
        starting = true
        message = ""
        Task {
            do { try await model.startMeeting(); started() }
            catch { message = userMessage(error, fallback: "Expo couldn't start listening. Check your audio settings and try again.") }
            starting = false
        }
    }
}

/// The question as a sheet on the main window.
struct StartMeetingSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        StartMeetingConfirmation(cancel: { model.presentingStart = false })
            .padding(22)
            .frame(width: 360)
            .background(Theme.background)
    }
}
