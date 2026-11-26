import AppKit
import Observation
import ServiceManagement

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var isError = true
    var offersPlans = false
}

enum Route: String, CaseIterable, Identifiable {
    case home, practice, history, profile, settings
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .home: "house"
        case .practice: "target"
        case .history: "clock.arrow.circlepath"
        case .profile: "person.crop.circle"
        case .settings: "gearshape"
        }
    }
}

struct RuntimeHealth: Equatable {
    var backend = LinkState.reconnecting
    var backendDetail = "Connecting…"
    var assistantReady: Bool?
    var assistantDetail = "Not checked yet."
    var transcriptionReady: Bool?
    var transcriptionDetail = "Not checked yet."
}

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable { case loading, ready, failed(String) }

    private(set) var phase = Phase.loading
    private(set) var config: AppConfig?
    var route = Route.home

    // Preferences of this Mac rather than of an account, so they work before sign-in.
    var showsWelcome = !Preference.bool("hasSeenWelcome", default: false) {
        didSet { Preference.set(!showsWelcome, "hasSeenWelcome") }
    }
    /// Set when the welcome tour ends on "Create account".
    @ObservationIgnored var startsAtRegistration = false
    var prefersHidden = Preference.bool("hideFromScreenShare", default: true) {
        didSet { Preference.set(prefersHidden, "hideFromScreenShare") }
    }
    var showsFloatingButton = Preference.bool("showFloatingButton", default: true) {
        didSet { Preference.set(showsFloatingButton, "showFloatingButton"); onOverlayChange() }
    }
    var sidebarCollapsed = Preference.bool("sidebarCollapsed", default: false) {
        didSet { Preference.set(sidebarCollapsed, "sidebarCollapsed") }
    }
    var selectedSessionID: String?
    var toasts: [Toast] = []
    private(set) var health = RuntimeHealth()
    private(set) var billing: BillingSummary?
    private(set) var cvBusy = false
    /// Set when macOS did not confirm that Expo is excluded from screen capture.
    private(set) var privacyFailure: String?
    static let privacyFailureMessage = "Assist stopped because Expo could not confirm it is hidden from screen sharing. Your session was preserved."
    @ObservationIgnored var onPrivacyRetry: () -> Void = {}
    @ObservationIgnored var canShowToast: () -> Bool = { true }
    /// The meeting brief is asked for before every Assist start.
    var presentingStart = false

    let store = AppStore()
    @ObservationIgnored private(set) var backend: BackendClient!
    private(set) var assist: AssistController!


    @ObservationIgnored var onPrivacyChange: (Bool) -> Void = { _ in }
    @ObservationIgnored var onOverlayChange: () -> Void = {}
    @ObservationIgnored var showMainWindow: () -> Void = {}
    @ObservationIgnored var showAssistantPanel: () -> Void = {}
    @ObservationIgnored var hideMainWindow: () -> Void = {}

    @ObservationIgnored private var passwordReset: (token: String, expiresAt: String)?
    @ObservationIgnored private var draftSync: Task<Void, Never>?
    @ObservationIgnored private var periodic: Task<Void, Never>?
    @ObservationIgnored private var checkoutWatch: Task<Void, Never>?

    var state: PersistedState { store.state }
    var capturePrivacy: CapturePrivacy {
        .resolve(prefersHidden: prefersHidden, allowed: state.screenHidingAllowed)
    }
    var isSignedIn: Bool { state.authenticated && state.account != nil }
    /// Floating controls are only offered to a fully set up account.
    var overlaysEligible: Bool { phase == .ready && isSignedIn && state.onboardingComplete }

    // MARK: Startup

    func start() async {
        phase = .loading
        do {
            let config = try AppConfig.load()
            self.config = config
            try store.load()
            backend = BackendClient(config: config)
            assist = AssistController(store: store, backend: backend)
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        assist.onError = { [weak self] in self?.report($0) }
        assist.onLifecycleChange = { [weak self] in self?.onOverlayChange() }
        // Applied before any floating window is shown.
        trackPrivacy()
        await backend.onSessionExpired { [weak self] in
            Task { @MainActor in await self?.sessionExpired() }
        }
        await restoreSession()
        phase = .ready
        await assist.recover()
        onOverlayChange()
        await refreshContentProtection()
        periodic?.cancel()
        periodic = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(600))
                await self?.refreshContentProtection()
            }
        }
        Task { await refreshHealth() }
        if isSignedIn { Task { await afterSignIn() } }
    }

    private func restoreSession() async {
        guard let token = store.token else {
            if state.authenticated { store.markSignedOut() }
            return
        }
        guard config?.isBackendConfigured == true else { store.markSignedOut(); return }
        await backend.setUserToken(token)
        do {
            store.activate(try await backend.currentUser())
        } catch let error as BackendError where error.status == 401 {
            await sessionExpired()
        } catch {
            // A temporary outage must not sign the user out or lose the retry queue.
        }
    }

    private func sessionExpired() async {
        guard isSignedIn else { return }
        await clearLocalSession()
        report(BackendError("Your session expired. Please sign in again."))
    }

    private func clearLocalSession() async {
        await assist.teardown()
        await backend.setUserToken(nil)
        passwordReset = nil
        try? store.setToken(nil)
        store.markSignedOut()
        billing = nil
        presentingStart = false
        selectedSessionID = nil
        route = .home
        onOverlayChange()
    }

    // MARK: Feedback

    func report(_ error: Error) {
        if error is CancellationError { return }
        let backendError = error as? BackendError
        let message = userMessage(error)
        push(Toast(message: message, offersPlans: backendError?.isPaywall == true))
        if !canShowToast() { Notifier.post(message, discreet: capturePrivacy.isHidden) }
    }

    func notify(_ message: String) { push(Toast(message: message, isError: false)) }

    private func push(_ toast: Toast) {
        guard !toasts.contains(where: { $0.message == toast.message }) else { return }
        toasts.append(toast)
        if toasts.count > 3 { toasts.removeFirst() }
        Task {
            try? await Task.sleep(for: .seconds(toast.offersPlans ? 12 : 6))
            toasts.removeAll { $0.id == toast.id }
        }
    }

    /// Runs an action and surfaces any failure.
    func attempt(_ action: () async throws -> Void) async -> Bool {
        do { try await action(); return true }
        catch { report(error); return false }
    }

    // MARK: Readiness

    /// The last audio test on this Mac. macOS cannot say whether computer audio
    /// capture is allowed, so a real test is the evidence.
    var audioTest: Readiness.AudioTest = switch Preference.string("audioTest") {
    case "passed": .passed
    case "failed": .failed
    default: .never
    }
    private(set) var permissionRevision = 0

    func permissionsMayHaveChanged() { permissionRevision += 1 }

    func runAudioTest() async -> AudioTestResult {
        let result = await AudioTester.run(settings: state.settings)
        audioTest = result.passed ? .passed : .failed
        Preference.set(result.passed ? "passed" : "failed", "audioTest")
        return result
    }

    var dockMinimized = false {
        didSet { if dockMinimized != oldValue { onOverlayChange() } }
    }
    var panelCompact = Preference.bool("panelCompact", default: false) {
        didSet { Preference.set(panelCompact, "panelCompact") }
    }

    var glanceMode = Preference.bool("glanceMode", default: false) {
        didSet { Preference.set(glanceMode, "glanceMode") }
    }

    // MARK: Robot

    private(set) var mark = Preference.string("mark").flatMap(MarkVariant.init(rawValue:)) ?? .standard
    private(set) var showsMarkPicker = Preference.string("mark").flatMap(MarkVariant.init(rawValue:)) == nil

    func chooseMark(_ choice: MarkVariant) {
        mark = choice
        showsMarkPicker = false
        Preference.set(choice.rawValue, "mark")
        applyDockIcon()
    }

    /// The Dock shows the choice while Expo runs. The icon in Applications is part
    /// of the signed app and stays the same.
    func applyDockIcon() {
        NSApp.applicationIconImage = mark == .standard ? nil : mark.nsImage(points: 512, tile: true)
    }

    // MARK: Welcome

    func finishWelcome(register: Bool) {
        startsAtRegistration = register
        showsWelcome = false
    }

    // MARK: Auth

    private func requireBackend() throws {
        guard config?.isBackendConfigured == true else {
            throw BackendError("Expo can't sign you in right now. Add your .env to ~/Library/Application Support/Expo, then restart Expo.")
        }
    }

    /// Returns the address awaiting verification, or nil once signed in.
    func signIn(email: String, password: String) async throws -> String? {
        try requireBackend()
        return try await complete(try await backend.signIn(email: email.trimmed, password: password))
    }

    func register(firstName: String, lastName: String, email: String, password: String) async throws -> String? {
        try requireBackend()
        return try await complete(try await backend.register(firstName: firstName.trimmed, lastName: lastName.trimmed, email: email.trimmed, password: password))
    }

    private func complete(_ result: AuthResult) async throws -> String? {
        switch result {
        case .verificationRequired(let email): return email
        case .signedIn(let session): try await activate(session); return nil
        }
    }

    func verifyEmail(_ email: String, code: String) async throws {
        try requireBackend()
        try await activate(try await backend.verifyEmail(email: email.trimmed, code: code.trimmed))
    }

    func resendCode(_ email: String) async throws {
        try requireBackend()
        try await backend.resendCode(email: email.trimmed)
    }

    func requestPasswordReset(_ email: String) async throws -> String {
        try requireBackend()
        passwordReset = nil
        return try await backend.requestPasswordReset(email: email.trimmed)
    }

    func verifyPasswordReset(_ email: String, code: String) async throws {
        // The reset ticket stays here and is never held by a view.
        passwordReset = try await backend.verifyPasswordReset(email: email.trimmed, code: code.trimmed)
    }

    func completePasswordReset(_ password: String) async throws {
        guard let ticket = passwordReset else { throw BackendError("Start a new password reset request.") }
        if let expiry = ISO.date(ticket.expiresAt), expiry <= Date() {
            passwordReset = nil
            throw BackendError("That reset session has expired. Start again.")
        }
        try await backend.completePasswordReset(token: ticket.token, password: password)
        passwordReset = nil
    }

    private func activate(_ session: AuthSession) async throws {
        await backend.setUserToken(session.token)
        do { try store.setToken(session.token) }
        catch { await backend.setUserToken(nil); throw error }
        store.activate(session.user)
        showsWelcome = false
        route = .home
        // Best effort: an outage never discards the cached profile or blocks sign-in.
        if let remote = try? await backend.profile() { store.update { $0.profile = remote.profile } }
        await assist.recover()
        onOverlayChange()
        await refreshContentProtection()
        Task { await afterSignIn() }
    }

    private func afterSignIn() async {
        await hydrateDraft()
        await refreshBilling()
        try? await syncSessions()
    }

    func signOut() async {
        await assist.pause()
        var warning: String?
        do { try await backend.logout() }
        catch { warning = "You're signed out on this device." }
        await clearLocalSession()
        await refreshContentProtection()
        if let warning { report(BackendError(warning)) } else { notify("You have been signed out of Expo.") }
    }

    func reset() async {
        // Deliberately tolerant: this runs when the app is already wedged.
        if assist.isActive { await assist.discard() }
        try? await backend.logout()
        await assist.teardown()
        await backend.setUserToken(nil)
        passwordReset = nil
        store.reset()
        billing = nil
        route = .home
        onOverlayChange()
    }

    // MARK: Health, privacy, billing

    func refreshHealth() async {
        guard let config, config.isBackendConfigured else {
            health = RuntimeHealth(backend: .offline, backendDetail: "Expo is not set up to connect yet.")
            return
        }
        health.backend = .reconnecting
        health.backendDetail = "Connecting…"
        guard await backend.isReady() else {
            health = RuntimeHealth(backend: .offline, backendDetail: "Can't connect right now. We'll keep retrying.",
                                   assistantReady: false, assistantDetail: "Waiting for Expo to come online.",
                                   transcriptionReady: false, transcriptionDetail: "Waiting for Expo to come online.")
            return
        }
        async let assistant = backend.assistantProviderDetail()
        async let transcription = backend.transcriptionProviderDetail()
        let (a, t) = await (assistant, transcription)
        health = RuntimeHealth(backend: .connected, backendDetail: config.backendURL.host() ?? "Connected",
                               assistantReady: a.ready, assistantDetail: a.detail,
                               transcriptionReady: t.ready, transcriptionDetail: t.detail)
    }

    /// Re-applies window protection whenever the choice, permission or account changes.
    private func trackPrivacy() {
        withObservationTracking {
            onPrivacyChange(capturePrivacy.isHidden)
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackPrivacy() }
        }
    }

    /// Stops listening and withdraws Expo's windows rather than risk exposing them.
    func privacyProtectionFailed() async {
        guard privacyFailure == nil, capturePrivacy.isHidden else { return }
        let wasActive = assist.isActive
        privacyFailure = wasActive ? Self.privacyFailureMessage : "Expo could not confirm it is hidden from screen sharing."
        onOverlayChange()
        hideMainWindow()
        report(BackendError(privacyFailure ?? ""))
        if wasActive { _ = await assist.end() }
    }

    func retryPrivacyProtection() {
        privacyFailure = nil
        onPrivacyRetry()
        onOverlayChange()
    }

    func setHiddenFromCapture(_ hidden: Bool) {
        guard capturePrivacy != .unavailable else { return }
        // Choosing to be visible, or hidden again, clears an earlier failure.
        if privacyFailure != nil { privacyFailure = nil; onOverlayChange() }
        prefersHidden = hidden
        // Windows change now rather than on the next observation pass.
        onPrivacyChange(capturePrivacy.isHidden)
    }

    func refreshContentProtection() async {
        // An outage keeps the last answer, and never changes the person's choice.
        let account = state.account?.id
        guard await backend.isAuthenticated,
              let allowed = try? await backend.contentProtection(),
              state.account?.id == account, state.screenHidingAllowed != allowed else { return }
        store.update { $0.screenHidingAllowed = allowed }
    }

    func refreshBilling() async {
        guard await backend.isAuthenticated else { billing = nil; return }
        billing = try? await backend.billing()
        await refreshContentProtection()
    }

    /// A server on this Mac takes no payments, so plans can be tried freely there.
    var plansAreTestOnly: Bool { config.map { AppConfig.isLoopback($0.backendURL) } ?? false }

    func choosePlan(_ plan: String, interval: String) async {
        guard plansAreTestOnly else { return await checkout(plan: plan, interval: interval) }
        _ = await attempt {
            guard await backend.isAuthenticated else { throw BackendError("Sign in to Expo before changing plan.") }
            try await backend.activateTestPlan(plan, interval: interval)
            await refreshBilling()
            notify("You are now on the \(plan.capitalized) plan (test mode, no charge).")
        }
    }

    func checkout(plan: String, interval: String) async {
        _ = await attempt {
            guard await backend.isAuthenticated else { throw BackendError("Sign in to Expo before upgrading.") }
            let result = try await backend.createCheckout(plan: plan, interval: interval)
            NSWorkspace.shared.open(result.url)
            // Safety net in case the payment webhook is late or lost.
            checkoutWatch?.cancel()
            checkoutWatch = Task { [weak self] in
                for _ in 0..<150 {
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled, let self else { return }
                    if (try? await self.backend.checkoutPaid(result.checkoutId)) == true {
                        await self.refreshBilling()
                        self.notify("Your plan is active.")
                        return
                    }
                }
            }
        }
    }

    // MARK: Assist entry points

    /// Every way of starting Assist goes through the meeting brief.
    func requestAssistStart() {
        if assist.isActive { showAssistantPanel(); return }
        route = .home
        selectedSessionID = nil
        showMainWindow()
        if overlaysEligible { presentingStart = true }
    }

    /// A live session for rehearsing: it always listens to the microphone and answers.
    func startPractice(_ kind: PracticeKind, topic: String) async throws {
        guard state.settings.captureMicrophone else {
            throw BackendError("Practice listens to your microphone. Turn on Include my microphone in Settings.")
        }
        try await startAssist(title: PracticeSession.title(kind, topic: topic),
                              brief: PracticeSession.brief(kind, topic: topic), remember: false)
    }

    func startAssist(title: String, brief: String, remember: Bool) async throws {
        dockMinimized = false
        guard overlaysEligible else { return }
        if let privacyFailure { throw BackendError(privacyFailure + " Use Retry Privacy Protection in the menu bar.") }
        // Ticking the box with empty text clears the saved brief.
        if remember { updateSettings { $0.savedBrief = String(brief.trimmed.prefix(MeetingBrief.maxCharacters)) } }
        try await assist.start(title: title, brief: brief)
        presentingStart = false
        if state.settings.minimizeOnStart { hideMainWindow() }
        showAssistantPanel()
    }

    func zoom(_ step: Int?) {
        let current = UIZoom.index(state.settings.uiZoom)
        let next = step.map { UIZoom.steps[min(UIZoom.steps.count - 1, max(0, current + $0))] } ?? 1
        updateSettings { $0.uiZoom = next }
    }

    // MARK: CV replacement

    /// Reads the new CV and holds it; the current one stays in use until approved.
    func replaceCv(_ file: URL) async throws {
        try requireCvAccess()
        guard !cvBusy else { return }
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if let problem = CvRules.problem(name: file.lastPathComponent, size: size) { throw BackendError(problem) }
        cvBusy = true
        defer { cvBusy = false }
        let account = state.account?.id
        let previous = state.pendingCvReplacement?.cv.uploadId
        let uploaded = try await backend.uploadCv(file: file, idempotencyKey: UUID().uuidString.lowercased())
        let completed = try await backend.waitForCv(uploaded)
        guard state.account?.id == account else { return }
        guard completed.status == "ready", var profile = completed.profile else {
            throw BackendError("We couldn't use this CV. Choose another PDF or Word document.", code: completed.errorCode)
        }
        profile.fullName = state.account?.fullName ?? profile.fullName
        let cv = CvMetadata(uploadId: completed.id, name: completed.name, size: completed.size, type: completed.type, uploadedAt: completed.uploadedAt)
        store.update { $0.pendingCvReplacement = PendingCvReplacement(cv: cv, profile: profile) }
        if previous != cv.uploadId { await dropUpload(previous) }
    }

    func approveCvReplacement() async throws {
        guard let pending = state.pendingCvReplacement else { throw BackendError("There is no new CV waiting for approval.") }
        let previous = state.cv?.uploadId
        // The assistant reads the account profile, so that is saved first.
        if await backend.isAuthenticated {
            try await backend.saveProfile(pending.profile, sourceUploadId: pending.cv.uploadId)
        }
        store.update {
            $0.cv = pending.cv
            $0.profile = pending.profile
            $0.pendingCvReplacement = nil
        }
        if previous != pending.cv.uploadId { await dropUpload(previous) }
    }

    func discardCvReplacement() async {
        guard let pending = state.pendingCvReplacement else { return }
        store.update { $0.pendingCvReplacement = nil }
        await dropUpload(pending.cv.uploadId)
    }

    /// A leftover upload is not worth failing the user's action for.
    private func dropUpload(_ id: String?) async {
        guard let id, await backend.isAuthenticated else { return }
        try? await backend.deleteCv(id)
    }

    func resumeAssist() async {
        if let privacyFailure { report(BackendError(privacyFailure)); return }
        await assist.resume()
        guard assist.snapshot.lifecycle == .listening else { return }
        showAssistantPanel()
        if state.settings.minimizeOnStart { hideMainWindow() }
    }

    func endAssist() async {
        guard let id = await assist.end() else { return }
        route = .history
        selectedSessionID = id
        showMainWindow()
        await refreshBilling()
    }

    func open(_ route: Route) {
        self.route = route
        selectedSessionID = nil
        showMainWindow()
    }

    func openSettings() {
        route = .settings
        selectedSessionID = nil
        showMainWindow()
    }

    // MARK: Consent, profile, settings

    func setConsent(cv: Bool? = nil, transcript: Bool? = nil) async {
        if let cv, let id = state.activeSessionId, isBackendID(id) {
            await syncProfileContext(id, enabled: cv && state.settings.useCvContext)
        }
        let now = ISO.now()
        var revoked = false
        store.update { state in
            func apply(_ record: inout ConsentRecord, _ value: Bool?) {
                guard let value, value != record.granted else { return }
                record = value
                    ? ConsentRecord(granted: true, grantedAt: now)
                    : ConsentRecord(granted: false, grantedAt: record.grantedAt, revokedAt: now)
            }
            if transcript == false && state.consent.transcriptCapture.granted { revoked = true }
            apply(&state.consent.cvProcessing, cv)
            apply(&state.consent.transcriptCapture, transcript)
        }
        if revoked { await assist.pause() }
    }

    private func syncProfileContext(_ id: String, enabled: Bool) async {
        guard await backend.isAuthenticated else { return }
        do { _ = try await backend.updateSession(id, .init(profileContextEnabled: enabled)) }
        catch { report(error) }
    }

    func updateSettings(_ mutate: (inout ExpoSettings) -> Void) {
        let before = state.settings
        store.update { mutate(&$0.settings) }
        let after = state.settings
        if before.useCvContext != after.useCvContext, let id = state.activeSessionId {
            Task { await syncProfileContext(id, enabled: after.useCvContext && state.consent.cvProcessing.granted) }
        }
        if before.launchAtLogin != after.launchAtLogin {
            do {
                if after.launchAtLogin { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                store.update { $0.settings.launchAtLogin = before.launchAtLogin }
                report(BackendError("macOS did not allow that change. Move Expo to Applications and try again."))
            }
        }
    }

    func saveProfile(_ profile: ProfessionalProfile) async throws {
        if !profile.yearsExperience.isEmpty, let problem = YearsRule.problem(profile.yearsExperience) { throw BackendError(problem) }
        if await backend.isAuthenticated {
            try await backend.saveProfile(profile, sourceUploadId: state.cv?.uploadId)
        }
        store.update { $0.profile = profile }
    }

    // MARK: Onboarding

    func saveDraft(_ mutate: (inout OnboardingDraft) -> Void) {
        guard isSignedIn, !state.onboardingComplete else { return }
        store.update { state in
            var draft = state.onboardingDraft ?? OnboardingDraft(profile: state.profile)
            mutate(&draft)
            draft.updatedAt = ISO.now()
            state.onboardingDraft = draft
        }
        draftSync?.cancel()
        draftSync = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self, let draft = self.state.onboardingDraft,
                  await self.backend.isAuthenticated, !self.state.onboardingComplete else { return }
            // The encrypted local draft remains the source if this fails.
            if let remote = try? await self.backend.saveOnboardingDraft(draft), !Task.isCancelled {
                self.store.update { $0.onboardingDraft?.remoteRevision = remote.revision }
            }
        }
    }

    private func hydrateDraft() async {
        guard await backend.isAuthenticated, !state.onboardingComplete else { return }
        guard let response = try? await backend.onboardingDraft() else { resumeCvIfNeeded(); return }
        let local = state.onboardingDraft
        if local == nil || response.revision > (local?.remoteRevision ?? 0) {
            store.update {
                $0.onboardingDraft = OnboardingDraft(
                    step: response.step, profile: response.profile, cvUploadId: response.cvUploadId,
                    cvName: response.cvName, cvStatus: response.cvStatus,
                    remoteRevision: response.revision, updatedAt: response.updatedAt
                )
                $0.profile = response.profile
            }
        }
        resumeCvIfNeeded()
    }

    private func resumeCvIfNeeded() {
        guard let draft = state.onboardingDraft, draft.cvUploadId != nil,
              !(draft.cvStatus == "ready" && state.cv != nil), draft.cvStatus != "rejected" else { return }
        Task { _ = await attempt { try await retryCv() } }
    }

    var canRetryCv: Bool {
        guard !cvBusy, let draft = state.onboardingDraft, draft.cvStatus != "ready", draft.cvStatus != "rejected" else { return false }
        return draft.cvUploadId != nil || draft.pendingFilePath != nil
    }

    func uploadCv(_ file: URL) async throws {
        try requireCvAccess()
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if let problem = CvRules.problem(name: file.lastPathComponent, size: size) { throw BackendError(problem) }
        let key = UUID().uuidString.lowercased()
        saveDraft {
            $0.step = 2; $0.cvName = file.lastPathComponent; $0.cvStatus = "idle"; $0.cvUploadId = nil
            $0.pendingFilePath = file.path; $0.idempotencyKey = key
        }
        try await runCv { try await self.backend.uploadCv(file: file, idempotencyKey: key) }
    }

    func retryCv() async throws {
        try requireCvAccess()
        guard let draft = state.onboardingDraft else { throw BackendError("There is no CV upload waiting for retry.") }
        try await runCv {
            if let id = draft.cvUploadId {
                let current = try await self.backend.cvUpload(id)
                return current.status == "failed" ? try await self.backend.reprocessCv(id) : current
            }
            guard let path = draft.pendingFilePath, let key = draft.idempotencyKey else {
                throw BackendError("There is no CV upload waiting for retry.")
            }
            return try await self.backend.uploadCv(file: URL(filePath: path), idempotencyKey: key)
        }
    }

    private func requireCvAccess() throws {
        guard state.consent.cvProcessing.granted else { throw BackendError("CV processing consent is required before upload.") }
        try requireBackend()
        guard isSignedIn else { throw BackendError("Your Expo sign-in session is missing or expired. Sign in again before uploading a CV.") }
    }

    private func runCv(_ begin: () async throws -> CvUpload) async throws {
        guard !cvBusy else { return }
        cvBusy = true
        defer { cvBusy = false }
        let account = state.account?.id
        let uploaded = try await begin()
        saveDraft { $0.cvUploadId = uploaded.id; $0.cvName = uploaded.name; $0.cvStatus = uploaded.status }
        let completed = try await backend.waitForCv(uploaded)
        // The account may have changed while the file was processing.
        guard state.account?.id == account else { return }
        guard completed.status == "ready", let extracted = completed.profile else {
            saveDraft { $0.cvStatus = completed.status }
            throw BackendError(completed.status == "rejected"
                ? "Expo rejected this CV. Choose another PDF or DOCX file."
                : "Expo could not finish processing this CV. Please try again.", code: completed.errorCode)
        }
        store.update { state in
            state.cv = CvMetadata(uploadId: completed.id, name: completed.name, size: completed.size, type: completed.type, uploadedAt: completed.uploadedAt)
            // What the person already typed wins over extraction.
            var merged = extracted
            let typed = state.onboardingDraft?.profile ?? state.profile
            merged.fullName = state.account?.fullName ?? extracted.fullName
            if !typed.preferredName.isEmpty { merged.preferredName = typed.preferredName }
            if !typed.title.isEmpty { merged.title = typed.title }
            if !typed.company.isEmpty { merged.company = typed.company }
            if !typed.industry.isEmpty { merged.industry = typed.industry }
            if !typed.yearsExperience.isEmpty { merged.yearsExperience = typed.yearsExperience }
            state.profile = merged
            state.onboardingDraft?.profile = merged
        }
        saveDraft { $0.step = 3; $0.cvStatus = "ready"; $0.pendingFilePath = nil; $0.idempotencyKey = nil }
    }

    func removeCv() async throws {
        if let id = state.cv?.uploadId, await backend.isAuthenticated { try await backend.deleteCv(id) }
        store.update { $0.cv = nil }
    }

    func completeOnboarding(_ profile: ProfessionalProfile) async throws {
        guard let account = state.account, await backend.isAuthenticated else {
            throw BackendError("Your Expo session has expired. Sign in again before finishing onboarding.")
        }
        var profile = profile
        profile.fullName = account.fullName
        if let problem = YearsRule.problem(profile.yearsExperience) { throw BackendError(problem) }
        let required = [profile.fullName, profile.preferredName, profile.title, profile.company, profile.industry, profile.yearsExperience]
        guard required.allSatisfy({ !$0.trimmed.isEmpty }) else { throw BackendError("Complete every profile field before continuing.") }
        guard let cv = state.cv else { throw BackendError("Upload and finish processing your CV before completing onboarding.") }
        guard state.consent.cvProcessing.granted else { throw BackendError("CV processing consent is required before completing onboarding.") }
        guard state.consent.transcriptCapture.granted else { throw BackendError("Transcript capture consent is required before completing onboarding.") }
        guard !profile.summary.trimmed.isEmpty, !profile.skills.isEmpty else {
            throw BackendError("Review your extracted profile and provide a summary and at least one skill.")
        }
        draftSync?.cancel()
        do {
            try await backend.saveProfile(profile, sourceUploadId: cv.uploadId)
            do { try await backend.clearOnboardingDraft() }
            catch let error as BackendError where error.status == 404 {}
        } catch {
            throw BackendError("Expo could not finish setup because your profile could not be synchronized. Check your connection and try again.")
        }
        store.update {
            $0.profile = profile
            $0.onboardingComplete = true
            $0.onboardingDraft = nil
        }
        onOverlayChange()
        await refreshContentProtection()
    }

    // MARK: Sessions

    private func merge(_ remote: [RemoteSession]) {
        store.update { state in
            for session in remote {
                if let index = state.sessions.firstIndex(where: { $0.id == session.id }) {
                    var merged = session.merged(into: state.sessions[index])
                    // The list is the authority on trash state.
                    merged.deletedAt = session.deletedAt
                    if state.sessions[index].status == "processing" && session.status == "active" { merged.status = "processing" }
                    state.sessions[index] = merged
                } else {
                    state.sessions.append(session.merged(into: nil))
                }
            }
        }
    }

    private func syncSessions() async throws {
        guard await backend.isAuthenticated else { return }
        async let active = backend.sessions(trash: false)
        async let deleted = backend.sessions(trash: true)
        let (a, d) = try await (active, deleted)
        merge(a.items + d.items)
    }

    /// Returns the next page cursor.
    func loadSessions(trash: Bool, cursor: String? = nil) async -> String? {
        guard await backend.isAuthenticated else { return nil }
        do {
            let page = try await backend.sessions(trash: trash, cursor: cursor)
            merge(page.items)
            return page.nextCursor
        } catch let error as BackendError where error.isTransient {
            return cursor
        } catch {
            report(error)
            return nil
        }
    }

    struct Match: Identifiable {
        var id: String { sessionID }
        var sessionID: String
        var snippet: String
        var count: Int
    }

    func search(_ query: String, trash: Bool) async throws -> (matches: [Match], offline: Bool) {
        let query = query.trimmed
        guard (2...200).contains(query.count) else { return ([], false) }
        if await backend.isAuthenticated {
            do {
                let page = try await backend.searchSessions(query, trash: trash)
                merge(page.items.map(\.session))
                return (page.items.map { Match(sessionID: $0.session.id, snippet: $0.matches.first.map { "\($0.label): \($0.snippet)" } ?? "", count: $0.matchCount) }, false)
            } catch let error as BackendError where error.isTransient {}
        }
        let matches = state.sessions.filter { ($0.deletedAt != nil) == trash }.compactMap { session -> Match? in
            var texts = [session.title] + session.transcript.map(\.text)
            texts += session.assistantMessages.map { "\($0.question) \($0.summary)" }
            if let notes = session.notes { texts += [notes.overview, notes.followUp] + notes.decisions + notes.keyPoints + notes.openQuestions + notes.actions.map(\.text) }
            let found = texts.filter { $0.localizedCaseInsensitiveContains(query) }
            return found.isEmpty ? nil : Match(sessionID: session.id, snippet: String(found[0].prefix(220)), count: found.count)
        }
        return (matches, true)
    }

    func loadSession(_ id: String) async throws {
        guard isBackendID(id), await backend.isAuthenticated else { return }
        async let overview = backend.sessionOverview(id)
        async let page = backend.transcript(id)
        var (remote, transcript) = try await (overview, page)
        remote.transcript = transcript.items
        var notes: NotesDetail?
        do { notes = try await backend.latestNotes(id) }
        catch let error as BackendError where error.status == 404 {}
        var session = remote.merged(into: store.session(id), notes: notes)
        session.transcriptCursor = transcript.nextCursor
        store.upsert(session)
    }

    func loadEarlierTranscript(_ id: String) async throws {
        guard let cursor = store.session(id)?.transcriptCursor else { return }
        let page = try await backend.transcript(id, before: cursor)
        store.updateSession(id) { session in
            let seen = Set(session.transcript.map(\.id))
            session.transcript = page.items.filter { !seen.contains($0.id) } + session.transcript
            session.transcriptCursor = page.nextCursor
        }
    }

    func generateNotes(_ id: String) async throws {
        guard state.consent.transcriptCapture.granted else { throw BackendError("Transcript consent is required before generating notes.") }
        guard await backend.isAuthenticated, isBackendID(id) else { throw BackendError("Sign in to Expo before generating notes for this session.") }
        store.updateSession(id) { $0.notesStatus = "pending"; $0.notesError = nil }
        do {
            try await backend.requestNotes(id)
            let notes = try await backend.waitForNotes(id)
            store.updateSession(id) { notes.apply(to: &$0) }
        } catch {
            store.updateSession(id) { $0.notesStatus = "failed"; $0.notesError = error.localizedDescription }
            throw error
        }
        await refreshBilling()
    }

    func saveSession(_ id: String, title: String? = nil, notes: SessionNotes? = nil) async throws {
        if await backend.isAuthenticated, isBackendID(id) {
            _ = try await backend.updateSession(id, .init(title: title, notes: notes))
        }
        store.updateSession(id) {
            if let title { $0.title = title }
            if let notes { $0.notes = notes }
        }
    }

    func deleteSession(_ id: String) async throws {
        if await backend.isAuthenticated, isBackendID(id) { try await backend.deleteSession(id) }
        store.updateSession(id) { $0.deletedAt = ISO.now() }
    }

    func restoreSession(_ id: String) async throws {
        if await backend.isAuthenticated, isBackendID(id) { _ = try await backend.restoreSession(id) }
        store.updateSession(id) { $0.deletedAt = nil }
    }
}

enum Preference {
    static func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
    static func string(_ key: String) -> String? { UserDefaults.standard.string(forKey: key) }
    static func set(_ value: Any, _ key: String) { UserDefaults.standard.set(value, forKey: key) }
}
