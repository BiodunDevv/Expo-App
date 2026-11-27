import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Zoom lays the page out smaller or larger, then scales it to the window.
        GeometryReader { proxy in
            let zoom = model.phase == .ready ? model.state.settings.uiZoom : 1
            page
                .frame(width: proxy.size.width / zoom, height: proxy.size.height / zoom)
                .scaleEffect(zoom, anchor: .topLeading)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .overlay(alignment: .top) { ToastStack() }
        .sheet(isPresented: Binding(get: { model.phase == .ready && model.presentingStart }, set: { model.presentingStart = $0 })) {
            StartMeetingSheet().environment(model).foregroundStyle(Theme.text)
        }
        .ignoresSafeArea()
    }

    private var page: some View {
        Group {
            switch model.phase {
            case .loading:
                VStack(spacing: 14) {
                    Logo(size: 56)
                    ProgressView().controlSize(.small)
                    Text("Opening Expo…").foregroundStyle(Theme.secondary)
                }
            case .failed(let message):
                VStack(spacing: 14) {
                    Logo(size: 56)
                    Text("Expo could not open").font(.title2.bold())
                    Text(message).multilineTextAlignment(.center).foregroundStyle(Theme.secondary).frame(maxWidth: 440)
                    HStack {
                        Button("Quit Expo") { NSApp.terminate(nil) }.buttonStyle(.expo(.secondary))
                        if message.contains("Keychain") {
                            Button("Open Keychain Access") {
                                if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.keychainaccess") {
                                    NSWorkspace.shared.openApplication(at: app, configuration: .init())
                                }
                            }
                            .buttonStyle(.expo(.secondary))
                        }
                        AsyncButton(title: "Retry") { await model.start() }
                    }
                }
            case .ready:
                if model.showsMarkPicker { MarkPickerView() }
                else if !model.isSignedIn && model.showsWelcome { WelcomeView() }
                else if !model.isSignedIn { AuthView() }
                else if !model.state.onboardingComplete { OnboardingView().id(model.state.account?.id) }
                else if let session = interrupted { RecoveryView(session: session) }
                else { Workspace() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A session left open by a previous run, not the one running now.
    private var interrupted: ExpoSession? {
        guard model.assist.snapshot.lifecycle == .paused,
              model.assist.snapshot.audio == .unknown else { return nil }
        return model.assist.currentSession
    }
}

private struct RecoveryView: View {
    @Environment(AppModel.self) private var model
    var session: ExpoSession
    @State private var confirmDiscard = false
    @State private var confirmReset = false

    var body: some View {
        VStack(spacing: 14) {
            Logo(size: 52)
            Text("Session recovery").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
            Text("An Assist session was interrupted").font(.system(size: 22, weight: .bold))
            Text("\(session.title) · \(ISO.display(session.startedAt)) · \(session.transcript.count) transcript turns")
                .foregroundStyle(Theme.secondary)
            HStack(spacing: 10) {
                Button("Discard") { confirmDiscard = true }.buttonStyle(.expo(.secondary))
                AsyncButton(title: "End and prepare notes", kind: .secondary) { await model.endAssist() }
                AsyncButton(title: "Resume Assist") { await model.resumeAssist() }
            }
            PrivacyToggle()
            Button("Still stuck? Reset Expo") { confirmReset = true }.buttonStyle(.expo(.plain, compact: true))
        }
        .padding(32)
        .rise()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog("Discard this interrupted session?", isPresented: $confirmDiscard) {
            Button("Discard session", role: .destructive) { Task { await model.assist.discard() } }
        } message: {
            Text("The unfinished transcript will move to deleted history and can be restored later from History.")
        }
        .confirmationDialog("Reset Expo on this device?", isPresented: $confirmReset) {
            Button("Reset Expo", role: .destructive) { Task { await model.reset() } }
        } message: {
            Text("This signs you out and clears local sessions and settings from this device. Anything already synced to your account stays there.")
        }
    }
}

private struct Workspace: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            Rectangle().fill(Theme.border).frame(width: 1)
            Group {
                if let id = model.selectedSessionID, model.store.session(id) != nil {
                    SessionDetailView(sessionID: id).id(id)
                } else {
                    switch model.route {
                    case .home: HomeView()
                    case .practice: PracticeView()
                    case .history: HistoryView()
                    case .profile: ProfileView()
                    case .settings: SettingsView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
