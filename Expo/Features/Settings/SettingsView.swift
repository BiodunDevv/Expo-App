import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmSignOut = false
    @State private var confirmReset = false
    @State private var apps: [AudioSourceApp] = []

    var body: some View {
        Page(title: "Settings", subtitle: "Shape how Expo behaves beside your work.", art: "art-assist") {
            Card(title: "Assist", icon: "bot") {
                toggle("Use CV context", "Include only approved and relevant context.", \.useCvContext)
                Hairline()
                ToggleRow(title: "Smart answers",
                          detail: smartLocked
                            ? "Included in Pro and Max. On your plan, tap “What should I say?” to get an answer."
                            : "Expo answers every question and request from the meeting on its own. Turn off to answer only when you ask. Applies to the next session.",
                          isOn: Binding(get: { model.state.settings.autoAnswer && !smartLocked },
                                        set: { value in model.updateSettings { $0.autoAnswer = value } }))
                    .disabled(smartLocked)
                Hairline()
                toggle("Send my voice too", "With smart answers on, what your microphone hears is answered as well.", \.answerOwnQuestions)
                toggle("Listen only", "Records the transcript and writes your notes without giving live answers. Applies to the next session.", \.listenOnly)
                Hairline()
                toggle("Minimize when Assist starts", "Return focus to your meeting application.", \.minimizeOnStart)
            }
            Card(title: "Answers", subtitle: "How Expo writes during a session.", icon: "chat") { AnswerSettings() }
            Card(title: "Audio", subtitle: "Computer output is the default. Selected application mode keeps unrelated system sounds out of the meeting context.", icon: "audio") {
                Picker("Capture mode", selection: setting(\.audioCaptureMode)) {
                    Text("Computer output (all screens)").tag(AudioCaptureMode.allSystemOutput)
                    Text("Selected application").tag(AudioCaptureMode.selectedApplication)
                }
                if model.state.settings.audioCaptureMode == .selectedApplication {
                    Picker("Capture source", selection: Binding(
                        get: { model.state.settings.audioSourceBundleID },
                        set: { id in model.updateSettings { $0.audioSourceBundleID = id; $0.audioSourceName = apps.first { $0.id == id }?.name } })) {
                        Text("Choose a meeting source").tag(String?.none)
                        ForEach(apps) { Text($0.name).tag(String?.some($0.id)) }
                        if let id = model.state.settings.audioSourceBundleID, !apps.contains(where: { $0.id == id }) {
                            Text("\(model.state.settings.audioSourceName ?? id) (not running)").tag(String?.some(id))
                        }
                    }
                }
                Hairline()
                toggle("Include my microphone", "On by default. Applies to the next Assist session and labels your speech as You.", \.captureMicrophone)
                Hairline()
                toggle("Warn when audio goes silent", "Show a clear warning after extended silence.", \.warnOnSilence)
                AudioTestRow()
            }
            Card(title: "Privacy & consent", subtitle: "Turning permission off stops future activity; it does not delete existing history.", icon: "shield") {
                ToggleRow(title: "CV processing", detail: "Allow CV upload, malware scanning, and profile extraction through the configured backend.", isOn: Binding(
                    get: { model.state.consent.cvProcessing.granted }, set: { value in Task { await model.setConsent(cv: value) } }))
                Hairline()
                ToggleRow(title: "Transcript capture", detail: "Allow permitted system-audio context and transcript text to be used for Assist.", isOn: Binding(
                    get: { model.state.consent.transcriptCapture.granted }, set: { value in Task { await model.setConsent(transcript: value) } }))
                Hairline()
                ToggleRow(title: "Hide from screen sharing",
                          detail: model.capturePrivacy == .unavailable
                            ? "Not available on this account. Your plan or administrator controls this."
                            : "Keeps Expo’s windows out of screenshots, recordings and screen shares. You can also switch this on the floating controls.",
                          isOn: Binding(get: { model.capturePrivacy.isHidden }, set: { model.setHiddenFromCapture($0) }))
                    .disabled(model.capturePrivacy == .unavailable)
                Text("The macOS setting is not a guarantee: some capture tools can still record Expo’s windows.")
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            }
            Card(title: "Your CV", subtitle: "Expo answers from the profile it reads from your CV.", icon: "resume") { CvReplaceSection() }
            plans
            Card(title: "Your Expo", subtitle: "The bot on the floating button, in the app and in the Dock.", icon: "star") {
                MarkGrid(selection: Binding(get: { model.mark }, set: { model.chooseMark($0) }))
            }
            Card(title: "Floating bot", icon: "chat") {
                ToggleRow(title: "Show floating bot", detail: "Keeps Expo one click away. It always appears during an Assist session.",
                          isOn: Binding(get: { model.showsFloatingButton }, set: { model.showsFloatingButton = $0 }))
            }
            Card(title: "See-through", subtitle: "How much of the screen shows through the floating windows.", icon: "app") {
                Picker("See-through", selection: setting(\.seeThrough)) {
                    ForEach(SeeThrough.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Card(title: "Email", subtitle: "You can change this for each session when you start or end it.", icon: "resume") {
                EmailChoice(isOn: setting(\.emailNotes))
            }
            Card(title: "Application", icon: "app") {
                toggle("Open Expo at login", "Start Expo quietly when you sign in to your Mac.", \.launchAtLogin)
                Hairline()
                toggle("Open main window maximized", "Applies the next time Expo launches.", \.openMaximized)
            }
            Card(title: "Account", subtitle: "Signing out revokes this device session and preserves your local account data.", icon: "profile") {
                HStack {
                    Button("Sign out") { confirmSignOut = true }.buttonStyle(.expo(.secondary))
                    Button("Reset Expo") { confirmReset = true }.buttonStyle(.expo(.danger))
                }
                if let config = model.config {
                    Text("Backend: \(config.backendURL.host() ?? config.backendURL.absoluteString)").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                }
            }
            Link("Icons and illustrations by Icons8", destination: URL(string: "https://icons8.com")!)
                .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
        }
        .task { apps = AudioCaptureService.sourceApps(); await model.refreshBilling() }
        .confirmationDialog("Sign out of Expo?", isPresented: $confirmSignOut) {
            Button("Sign out") { Task { await model.signOut() } }
        }
        .confirmationDialog("Reset Expo on this device?", isPresented: $confirmReset) {
            Button("Reset Expo", role: .destructive) { Task { await model.reset() } }
        } message: {
            Text("This signs you out and clears local sessions and settings from this device. Anything already synced to your account stays there.")
        }
    }

    private var smartLocked: Bool { model.billing?.smartAnswersLocked == true }

    private var plans: some View { PlanSection() }

    private func setting<T>(_ path: WritableKeyPath<ExpoSettings, T>) -> Binding<T> {
        Binding(get: { model.state.settings[keyPath: path] }, set: { value in model.updateSettings { $0[keyPath: path] = value } })
    }

    private func toggle(_ title: String, _ detail: String, _ path: WritableKeyPath<ExpoSettings, Bool>) -> some View {
        ToggleRow(title: title, detail: detail, isOn: setting(path))
    }
}
