import SwiftUI
import ThinkingOrbsKit
import UniformTypeIdentifiers

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var profile = ProfessionalProfile()
    @State private var skills = ""
    @State private var message = ""
    @State private var picking = false
    @State private var restored = false
    @State private var audioPassed = false
    /// Keeps the detail fields open once they have been needed.
    @State private var editingDetails = false

    private static let titles = ["Welcome", "Your work", "Your CV", "Review", "Assistance", "Audio", "Ready"]
    private static let art = ["art-welcome", "art-work", "art-cv", "art-review", "art-assist", "art-audio", "art-ready"]
    private static let hints = [
        "About two minutes. Your progress is saved as you go.",
        "Fill what you like now. Your CV can supply the rest.",
        "Expo reads it and fills in your profile.",
        "Check the details and complete anything missing.",
        "You can change these later in Settings.",
        "One quick test proves Expo can hear your meetings.",
        "Everything is set.",
    ]

    var body: some View {
        HStack(spacing: 0) {
            guide
            Rectangle().fill(Theme.border).frame(width: 1)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        content
                        if !message.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text(message).fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.system(size: 12)).foregroundStyle(Theme.danger)
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.dangerSoft, in: .rect(cornerRadius: 16))
                        }
                    }
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 28).padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
                    .id(step)
                    .transition(.opacity.combined(with: .offset(y: 8)))
                }
                .defaultScrollAnchor(.center)
                .scrollBounceBehavior(.basedOnSize)
                Hairline()
                footer
            }
            .frame(maxWidth: .infinity)
        }
        .animation(.snappy(duration: 0.28), value: step)
        .onAppear(perform: restore)
        .onChange(of: profile) { if restored { model.saveDraft { $0.profile = profile } } }
        .onChange(of: model.state.cv) { adoptExtraction() }
        .onChange(of: step, initial: true) { _, now in if now == 3 && !missing.isEmpty { editingDetails = true } }
        .onChange(of: model.state.onboardingDraft?.remoteRevision) { old, new in if old == nil && new != nil && step == 0 { restore() } }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf, UTType(filenameExtension: "docx") ?? .data]) { result in
            guard case .success(let url) = result else { return }
            message = ""
            Task {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do { try await model.uploadCv(url) } catch { message = error.localizedDescription }
            }
        }
    }

    /// Where the person is: a picture for this step and the list of all steps.
    private var guide: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Logo(size: 26)
                Text("Set up Expo").font(.system(size: 14, weight: .bold))
            }
            Spacer(minLength: 8)
            Image(Self.art[step]).resizable().interpolation(.high).scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 210)
                .id(step)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .accessibilityHidden(true)
            Text(Self.hints[step]).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Self.titles.indices, id: \.self) { index in stepRow(index) }
            }
        }
        .padding(.horizontal, 20).padding(.top, 38).padding(.bottom, 18)
        .frame(width: 280)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar)
    }

    /// Finished steps can be revisited.
    private func stepRow(_ index: Int) -> some View {
        Button { move(index) } label: {
            HStack(spacing: 9) {
                ZStack {
                    Circle().fill(index <= step ? Theme.accent : .clear)
                    Circle().stroke(index <= step ? Theme.accent : Theme.border, lineWidth: 1)
                    if index < step { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)) }
                    else { Text("\(index + 1)").font(.system(size: 9.5, weight: .bold)) }
                }
                .foregroundStyle(index <= step ? Theme.onAccent : Theme.tertiary)
                .frame(width: 18, height: 18)
                Text(Self.titles[index]).font(.system(size: 12, weight: index == step ? .bold : .medium))
                    .foregroundStyle(index <= step ? Theme.text : Theme.tertiary)
                Spacer()
            }
            .padding(.horizontal, 8).frame(height: 27)
            .background(index == step ? Theme.selected : .clear, in: .rect(cornerRadius: 13))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(index >= step)
        .accessibilityLabel("Step \(index + 1), \(Self.titles[index])")
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if step > 0 { Button("Back") { move(step - 1) }.buttonStyle(.expo(.secondary)) }
            PrivacyToggle()
            Button("Sign out") { Task { await model.signOut() } }.buttonStyle(.expo(.plain, compact: true))
            Spacer()
            if step < 6 {
                Button(step == 0 ? "Get started" : step == 3 ? "Confirm profile" : "Continue") { advance() }
                    .buttonStyle(.expo)
                    .keyboardShortcut(.defaultAction)
                    .disabled(step == 2 && (model.state.cv == nil || model.cvBusy))
            } else {
                AsyncButton(title: "Open Expo", busyTitle: "Saving…") {
                    message = ""
                    do { try await model.completeOnboarding(profile) }
                    catch { message = error.localizedDescription }
                }
            }
        }
        .padding(.horizontal, 20).frame(height: 62)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0:
            heading("Welcome\(model.state.account.map { ", \($0.firstName)" } ?? "")", "Expo quietly follows permitted conversations, then gives concise help when you ask.")
            feature("doc.text", "Add your CV", "So answers sound like you")
            feature("waveform", "Test your audio", "So Expo hears the meeting")
            feature("sparkles", "Start Assist", "Live transcript, answers and notes")
        case 1:
            heading("Tell Expo about your work", "Complete these details so Expo can tailor professional suggestions to you.")
            Field(label: "Full name", text: $profile.fullName, disabled: true)
            detailFields
        case 2:
            heading("Add your CV or résumé", "Your original file stays in Expo until you choose to remove it.")
            ToggleRow(title: "I consent to CV processing", detail: "Expo may upload this CV to the configured backend for malware scanning and professional-profile extraction.", isOn: consent(\.cvProcessing) { value in
                Task { await model.setConsent(cv: value) }
            })
            HStack(spacing: 10) {
                Button(model.state.cv == nil ? "Choose PDF or DOCX" : "Choose another file") { picking = true }
                    .buttonStyle(.expo(.secondary))
                    .disabled(!model.state.consent.cvProcessing.granted || model.cvBusy)
                if model.cvBusy {
                    ThinkingOrb(state: .searching, size: .px20)
                    Text("\(model.state.onboardingDraft?.cvStatus?.capitalized ?? "Uploading")…").foregroundStyle(Theme.secondary)
                } else if let cv = model.state.cv {
                    Label(cv.name, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.success)
                } else if model.canRetryCv {
                    AsyncButton(title: "Retry upload", kind: .secondary) {
                        do { try await model.retryCv(); message = "" } catch { message = error.localizedDescription }
                    }
                }
            }
            .font(.system(size: 12))
        case 3:
            heading("Review what Expo found", "Edit anything that is not right.")
            if !missing.isEmpty || editingDetails {
                Card(title: "A few details are missing") { detailFields }
            }
            Field(label: "Professional summary", text: $profile.summary, multiline: true)
            Field(label: "Skills (comma separated)", text: $skills, multiline: true)
                .onChange(of: skills) { profile.skills = Self.split(skills) }
            ProfileHighlights(profile: profile)
        case 4:
            heading("Tune your assistance", "Choose how answers are written. Change this later in Settings.")
            AnswerSettings()
            ToggleRow(title: "Relevant CV context", detail: "Used only when your question benefits from it.", isOn: Binding(
                get: { model.state.settings.useCvContext },
                set: { value in model.updateSettings { $0.useCvContext = value } }))
        case 5:
            heading("System audio", "Expo captures computer output and your microphone. You can turn the microphone off in Settings. Raw audio is mixed in memory and never stored.")
            ToggleRow(title: "I consent to transcript capture", detail: "Expo may capture permitted computer-output audio and, unless you turn it off, microphone audio. It sends audio to the transcription provider and transcript text for assistance. Revoking this stops future capture; it does not delete existing history.", isOn: consent(\.transcriptCapture) { value in
                Task { await model.setConsent(transcript: value) }
            })
            AudioTestRow { audioPassed = $0 }
            Text("Expo plays a short sound and checks that it can hear it. The test must pass to continue.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
        default:
            heading("Expo is ready", "You’ll always see whether Expo is listening or recovering its audio connection. Press ⌘↩ to ask, ⇧⌘↩ to ask about your screen.")
        }
    }

    @ViewBuilder private var detailFields: some View {
        HStack { Field(label: "Preferred name", text: $profile.preferredName); Field(label: "Role or title", text: $profile.title) }
        HStack { Field(label: "Company", text: $profile.company); Field(label: "Industry", text: $profile.industry) }
        Field(label: "Years of experience", text: $profile.yearsExperience, digitsOnly: true)
    }

    private var missing: [String] {
        [("preferred name", profile.preferredName), ("role", profile.title), ("company", profile.company),
         ("industry", profile.industry), ("years of experience", profile.yearsExperience)]
            .filter { $0.1.trimmed.isEmpty }.map(\.0)
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 14)).frame(width: 36, height: 36)
                .background(Theme.subtle, in: .rect(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
            }
        }
    }

    private func heading(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 19, weight: .bold))
            Text(body).font(.system(size: 13)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func consent(_ path: KeyPath<ConsentState, ConsentRecord>, _ set: @escaping @MainActor @Sendable (Bool) -> Void) -> Binding<Bool> {
        Binding(get: { model.state.consent[keyPath: path].granted }, set: set)
    }

    static func split(_ text: String) -> [String] {
        text.split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }
    }

    private func restore() {
        let draft = model.state.onboardingDraft
        profile = draft?.profile ?? model.state.profile
        profile.fullName = model.state.account?.fullName ?? profile.fullName
        skills = profile.skills.joined(separator: ", ")
        step = min(6, max(0, draft?.step ?? 0))
        restored = true
    }

    private func adoptExtraction() {
        guard model.state.cv != nil else { return }
        profile = model.state.profile
        skills = profile.skills.joined(separator: ", ")
        if step == 2 { step = 3 }
    }

    private func advance() {
        message = ""
        // Details may wait until after the CV; they are required before confirming.
        if step == 3 && !missing.isEmpty {
            editingDetails = true
            message = "Add your \(missing.formatted(.list(type: .and))) to continue."; return
        }
        if step == 3 && (profile.summary.trimmed.isEmpty || profile.skills.isEmpty) {
            message = "Add a professional summary and at least one skill."; return
        }
        if step == 5 && !model.state.consent.transcriptCapture.granted {
            message = "Grant transcript consent to continue."; return
        }
        if step == 5 && !audioPassed {
            message = "Run the audio test and make sure computer output passes before continuing."; return
        }
        if (step == 1 && !profile.yearsExperience.trimmed.isEmpty) || step == 3,
           let problem = YearsRule.problem(profile.yearsExperience) { editingDetails = true; message = problem; return }
        move(step + 1)
    }

    private func move(_ next: Int) {
        message = ""
        step = next
        model.saveDraft { $0.step = next; $0.profile = profile }
    }
}

struct ProfileHighlights: View {
    var profile: ProfessionalProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("Experience", profile.roles.map { "\($0.role) · \($0.company) · \($0.period)" })
            section("Education", profile.education.map { "\($0.qualification) · \($0.school)" })
            section("Projects", profile.projects.map { "\($0.name) — \($0.summary)" })
            section("Certifications", profile.certifications)
        }
    }

    @ViewBuilder private func section(_ title: String, _ rows: [String]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .semibold))
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Text(row).font(.system(size: 12)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
