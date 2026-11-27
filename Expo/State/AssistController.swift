import Foundation
import Observation

/// The Assist session lifecycle: capture, transcription, realtime, questions,
/// and a local-first sync queue that survives outages and restarts.
@MainActor
@Observable
final class AssistController {
    private(set) var snapshot = AssistSnapshot() {
        didSet { if lifecycle != snapshot.lifecycle { lifecycle = snapshot.lifecycle } }
    }
    private(set) var preview: TranscriptionResult?

    // Question state shared by the assistant panel.
    private(set) var pendingQuestion: String?
    private(set) var pendingScreen = false
    /// The snapshot's state on its own, so menus are not redrawn every second.
    private(set) var lifecycle = AssistSnapshot().lifecycle
    /// Captured pictures by answer, in memory until the session ends.
    private(set) var screenshots: [String: String] = [:]
    private(set) var streamedText = ""
    private(set) var isAsking = false
    /// Loudness of the captured audio, 0 to 1.
    private(set) var level = 0.0
    @ObservationIgnored private var askTask: Task<Void, Never>?
    /// Answer questions as they are asked, or only keep the transcript.
    private(set) var autoAnswer = true
    /// Words heard that are about to be sent.
    private(set) var heardQuestion = ""
    @ObservationIgnored private var turn = SpeechTurn()
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?

    @ObservationIgnored var onError: (BackendError) -> Void = { _ in }
    @ObservationIgnored var onLifecycleChange: () -> Void = {}

    @ObservationIgnored private let store: AppStore
    @ObservationIgnored private let backend: BackendClient
    @ObservationIgnored private let audio = AudioCaptureService()
    @ObservationIgnored private let transcription: TranscriptionClient
    @ObservationIgnored private let realtime: RealtimeClient

    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var transitioning = false
    /// Whether the microphone actually joined the current capture.
    private(set) var capturingMicrophone = false
    @ObservationIgnored private var recovering = false
    @ObservationIgnored private var lastOutageNotice: Date?
    @ObservationIgnored private var microphoneNoticeShown = false
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var notesRefreshWanted = false
    @ObservationIgnored private var syncedSegments = Set<String>()
    @ObservationIgnored private var syncedMessages = Set<String>()
    @ObservationIgnored private var pendingMessageSessions = Set<String>()
    @ObservationIgnored private var flushing = false
    @ObservationIgnored private var finalizing = false
    @ObservationIgnored private var heldSegments: [UUID: Task<Void, Never>] = [:]

    init(store: AppStore, backend: BackendClient) {
        self.store = store
        self.backend = backend
        transcription = TranscriptionClient(backend: backend)
        realtime = RealtimeClient(backend: backend)
    }

    var isActive: Bool {
        snapshot.sessionId != nil || [.connecting, .listening, .paused].contains(snapshot.lifecycle)
    }

    var currentSession: ExpoSession? { store.session(snapshot.sessionId ?? store.state.activeSessionId) }

    private var hasConsent: Bool { store.state.consent.transcriptCapture.granted }

    private func isCurrent(_ id: String, _ expected: Int) -> Bool {
        generation == expected && snapshot.sessionId == id
    }

    private func set(_ mutate: (inout AssistSnapshot) -> Void) {
        let before = snapshot.lifecycle
        mutate(&snapshot)
        if before != snapshot.lifecycle { onLifecycleChange() }
    }

    // MARK: Lifecycle

    func start(title: String = "", brief: String = "") async throws {
        guard !transitioning else { return }
        transitioning = true
        defer { transitioning = false }
        guard hasConsent else { throw BackendError("Transcript consent is required before starting Assist.") }
        if [.listening, .paused].contains(snapshot.lifecycle) { return }
        guard await backend.isAuthenticated else {
            throw BackendError("Sign in to Expo before starting Assist. Your meeting session must be owned by your account.")
        }
        generation += 1
        let expected = generation
        lastOutageNotice = nil
        screenshots = [:]
        microphoneNoticeShown = false
        // Practice is for seeing answers, whatever real sessions are set to.
        autoAnswer = PracticeSession.isPractice(title) || (store.state.settings.autoAnswer && !store.state.settings.listenOnly)
        set { $0 = AssistSnapshot(lifecycle: .connecting) }
        var created: String?
        do {
            let settings = store.state.settings
            let remote = try await backend.createSession(
                title: String(title.trimmed.prefix(200)).nonEmpty ?? "Meeting session", startedAt: ISO.now(),
                profileContextEnabled: settings.useCvContext && store.state.consent.cvProcessing.granted,
                prepNotes: String(brief.trimmed.prefix(MeetingBrief.maxCharacters)).nonEmpty,
                emailNotes: settings.emailNotes
            )
            created = remote.id
            var session = remote.merged(into: nil)
            session.prepNotes = brief.trimmed.nonEmpty
            session.emailNotes = settings.emailNotes
            store.upsert(session)
            store.update { $0.activeSessionId = session.id }
            syncedSegments = []
            syncedMessages = []
            set { $0.sessionId = session.id }
            guard hasConsent else { throw BackendError("Transcript consent is required before starting Assist.") }
            try await startCapture(session.id, expected)
            guard isCurrent(session.id, expected) else { return }
            set { $0 = AssistSnapshot(lifecycle: .listening, audio: .ready, elapsedSeconds: session.durationSeconds, sessionId: session.id) }
            startClock()
            startSync()
            startRealtime(session.id)
        } catch {
            await stopCapture()
            realtime.stop()
            // A provider or audio failure must not erase a session that exists.
            if let created {
                store.updateSession(created) { $0.status = "recovered" }
                store.update { $0.activeSessionId = created }
            }
            if generation == expected {
                set {
                    $0 = AssistSnapshot(lifecycle: .error, connection: .reconnecting, audio: error is AudioCaptureError ? .unavailable : .unknown,
                                        sessionId: created, error: error.localizedDescription)
                }
            }
            throw error
        }
    }

    func pause() async {
        guard snapshot.lifecycle == .listening else { return }
        retryTask?.cancel()
        set { $0.lifecycle = .paused; $0.recoveryAttempt = nil; $0.recoveryMaxAttempts = nil }
        clockTask?.cancel()
        await stopCapture()
    }

    func resume() async {
        guard !transitioning, hasConsent, snapshot.lifecycle == .paused, let id = snapshot.sessionId else { return }
        transitioning = true
        defer { transitioning = false }
        let expected = generation
        set { $0.lifecycle = .connecting; $0.audio = .unknown; $0.error = nil }
        do {
            try await startCapture(id, expected)
            guard isCurrent(id, expected) else { return }
            set { $0.lifecycle = .listening; $0.audio = .ready; $0.connection = .connected; $0.error = nil }
            store.updateSession(id) { $0.status = "active" }
            startClock()
            startSync()
            startRealtime(id)
        } catch {
            await stopCapture()
            guard isCurrent(id, expected) else { return }
            set { $0.lifecycle = .paused; $0.audio = .unavailable; $0.error = error.localizedDescription }
            onError(BackendError(error.localizedDescription))
        }
    }

    /// Returns whether listening is working again. A quiet retry raises no alert.
    @discardableResult
    func retryListening(quiet: Bool = false) async -> Bool {
        guard !transitioning, hasConsent, let id = snapshot.sessionId ?? store.state.activeSessionId else { return false }
        if !quiet { retryTask?.cancel() }
        transitioning = true
        defer { transitioning = false }
        generation += 1
        let expected = generation
        await stopCapture()
        guard generation == expected else { return false }
        set {
            $0.lifecycle = .connecting; $0.connection = .reconnecting; $0.audio = .unknown
            $0.sessionId = id; $0.error = nil
        }
        do {
            try await startCapture(id, expected)
            guard isCurrent(id, expected) else { return false }
            set { $0.lifecycle = .listening; $0.connection = .connected; $0.audio = .ready; $0.recoveryAttempt = nil; $0.recoveryMaxAttempts = nil }
            store.updateSession(id) { $0.status = "active" }
            startClock()
            startSync()
            startRealtime(id)
            return true
        } catch {
            await stopCapture()
            guard isCurrent(id, expected) else { return false }
            let permanent = (error as? AudioCaptureError)?.permanent == true
            let message = "Expo could not restore meeting audio. Your session is still open and its history is preserved. \(error.localizedDescription)"
            set {
                $0.lifecycle = .listening; $0.audio = .unavailable; $0.error = message
                $0.recoveryAttempt = nil; $0.recoveryMaxAttempts = nil
            }
            startClock()
            if !quiet {
                announceOutage(message)
                if !permanent { recoverAutomatically(id) }
            }
            return false
        }
    }

    @discardableResult
    func end() async -> String? {
        guard let id = snapshot.sessionId ?? store.state.activeSessionId else { return nil }
        retryTask?.cancel()
        clockTask?.cancel()
        generation += 1
        let duration = max(snapshot.elapsedSeconds, store.session(id)?.durationSeconds ?? 0)
        set { $0.lifecycle = .generatingNotes; $0.sessionId = nil; $0.error = nil }
        let remote = isBackendID(id)
        // History is committed before provider cleanup, so a hung stop can
        // never leave the app believing the session is still resumable.
        store.updateSession(id) {
            $0.status = remote ? "processing" : "complete"
            $0.endedAt = ISO.now()
            $0.durationSeconds = duration
            if remote { $0.notes = nil; $0.notesStatus = "pending"; $0.notesError = nil }
        }
        store.update { $0.activeSessionId = nil }
        await stopCapture()
        preview = nil
        pendingQuestion = nil
        streamedText = ""
        screenshots = [:]
        set { $0 = AssistSnapshot(lifecycle: .completed) }
        startSync()
        Task { await finalize(id) }
        return id
    }

    func discard() async {
        generation += 1
        clockTask?.cancel()
        let id = store.state.activeSessionId ?? snapshot.sessionId
        await stopCapture()
        realtime.stop()
        if let id {
            // A backend outage must not strand the user on the recovery screen.
            if await backend.isAuthenticated, isBackendID(id) { try? await backend.deleteSession(id) }
            store.updateSession(id) { $0.deletedAt = ISO.now() }
            store.update { $0.activeSessionId = nil }
        }
        set { $0 = AssistSnapshot() }
    }

    /// Restores an interrupted session, or finishes syncing one that ended offline.
    func recover() async {
        for session in store.state.sessions where isBackendID(session.id) && !session.assistantMessages.isEmpty {
            pendingMessageSessions.insert(session.id)
        }
        if let active = store.session(store.state.activeSessionId) {
            guard isBackendID(active.id), ["active", "recovered"].contains(active.status) else {
                store.update { $0.activeSessionId = nil }
                return
            }
            set { $0 = AssistSnapshot(lifecycle: .paused, audio: .unknown, elapsedSeconds: active.durationSeconds, sessionId: active.id) }
            startSync()
            if await backend.isAuthenticated { startRealtime(active.id) }
            return
        }
        guard await backend.isAuthenticated else { return }
        if store.state.sessions.contains(where: { $0.status == "processing" && $0.endedAt != nil }) || !pendingMessageSessions.isEmpty {
            startSync()
        }
    }

    /// Used on sign-out and reset.
    func teardown() async {
        retryTask?.cancel()
        generation += 1
        clockTask?.cancel(); syncTask?.cancel(); refreshTask?.cancel()
        syncTask = nil; refreshTask = nil
        await stopCapture()
        realtime.stop()
        syncedSegments = []; syncedMessages = []; pendingMessageSessions = []
        preview = nil; pendingQuestion = nil; streamedText = ""; isAsking = false
        set { $0 = AssistSnapshot() }
    }

    /// Applies at once and is remembered. Expo decides here which words are
    /// questions, so nothing changes on the server.
    func setAutoAnswer(_ on: Bool) async {
        guard on != autoAnswer else { return }
        autoAnswer = on
        // A practice session's switch does not change how real sessions start.
        if !isPractice { store.update { $0.settings.autoAnswer = on; if on { $0.settings.listenOnly = false } } }
        if !on { forgetHeard() }
    }

    // MARK: Sending what is heard

    var isPractice: Bool { currentSession.map { PracticeSession.isPractice($0.title) } ?? false }

    /// In practice the person's own voice is the point, so it is always sent.
    private var sendsOwnVoice: Bool { isPractice || store.state.settings.answerOwnQuestions }

    /// What is being said right now, shown in the message box.
    var liveQuestion: String {
        guard autoAnswer, snapshot.lifecycle == .listening else { return "" }
        guard let preview, !isFromMicrophone(preview) || sendsOwnVoice else { return heardQuestion }
        return [heardQuestion, preview.text.trimmed].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func isFromMicrophone(_ result: TranscriptionResult) -> Bool {
        result.source == "microphone" || (result.source == nil && capturingMicrophone && result.channelIndex == 0)
    }

    /// Every finished line is sent at the next pause.
    private func consider(_ segment: TranscriptSegment, in id: String) {
        guard autoAnswer, segment.speaker != ScreenAnswer.speaker, segment.speaker != "You" || sendsOwnVoice else { return }
        guard turn.add(segment.text) else { return }
        heardQuestion = turn.text
        sendHeard(in: id)
    }

    private func sendHeard(in id: String) {
        sendTask?.cancel()
        sendTask = Task { [weak self] in
            try? await Task.sleep(for: SpeechTurn.settle)
            // Waits while someone is still talking, and while an answer is being
            // written; words heard meanwhile join the next message.
            var waited = 0
            while let self, !Task.isCancelled, self.isAsking || (waited < 16 && self.preview != nil) {
                try? await Task.sleep(for: .milliseconds(250))
                waited += 1
            }
            guard let self, !Task.isCancelled, self.autoAnswer, self.snapshot.lifecycle == .listening,
                  self.store.state.activeSessionId == id else { return }
            let message = self.turn.take(at: Date())
            self.heardQuestion = ""
            if let message { self.submit(message) }
        }
    }

    /// The person took the words over, or dismissed them.
    func forgetHeard() {
        sendTask?.cancel()
        heardQuestion = ""
        turn.clear()
    }

    // MARK: Automatic recovery

    /// Keeps trying to bring listening back, a little less often each time.
    private func announceOutage(_ message: String) {
        guard Recovery.shouldAnnounce(last: lastOutageNotice, now: Date()) else { return }
        lastOutageNotice = Date()
        onError(BackendError(message))
    }

    private func recoverAutomatically(_ id: String) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            var delay = 3
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled, self.store.state.activeSessionId == id,
                      self.snapshot.lifecycle == .listening else { return }
                guard self.snapshot.audio == .unavailable || self.snapshot.connection == .offline else { return }
                if await self.retryListening(quiet: true) { return }
                delay = min(30, delay * 2)
            }
        }
    }

    // MARK: Capture

    private func startCapture(_ id: String, _ expected: Int) async throws {
        transcription.onTranscript = { [weak self] in self?.receive($0, id, expected) }
        transcription.onFailure = { [weak self] in self?.transcriptionFailed($0, id, expected) }
        transcription.onReady = { [weak self] in
            guard let self, self.isCurrent(id, expected), self.snapshot.lifecycle == .listening else { return }
            self.set { $0.connection = .connected; $0.audio = .ready; $0.error = nil; $0.recoveryAttempt = nil; $0.recoveryMaxAttempts = nil }
        }
        let settings = store.state.settings
        // The server must not answer on its own: it replies to any sentence, while
        // Expo answers only real questions.
        try? await backend.setAiControls(id, paused: false, autoAnswer: false)
        try await transcription.start(sessionId: id, channels: settings.captureMicrophone ? 2 : 1)
        guard isCurrent(id, expected) else { await transcription.stop(); return }
        capturingMicrophone = try await audio.start(settings: settings) { [weak self] frame in
            self?.transcription.send(frame)
            self?.level = AudioLevel.of(frame)
        }
        if settings.captureMicrophone && !capturingMicrophone && !microphoneNoticeShown {
            microphoneNoticeShown = true
            onError(BackendError("Your microphone is unavailable, so Expo is capturing computer audio only."))
        }
    }

    private func stopCapture() async {
        forgetHeard()
        preview = nil
        audio.stop()
        level = 0
        await transcription.stop()
    }

    private func receive(_ result: TranscriptionResult, _ id: String, _ expected: Int) {
        guard hasConsent, isCurrent(id, expected), [.listening, .connecting].contains(snapshot.lifecycle) else { return }
        guard result.isFinal else { preview = result; return }
        if preview?.segmentId == result.segmentId { preview = nil }
        let fromMicrophone = result.source == "microphone"
            || (result.source == nil && capturingMicrophone && result.channelIndex == 0)
        let segment = TranscriptSegment(
            id: result.segmentId, at: offset(id, result.at), speaker: fromMicrophone ? "You" : "Meeting",
            text: result.text.trimmed, confidence: result.confidence,
            source: result.source, channelIndex: result.channelIndex
        )
        guard fromMicrophone else { keep(segment, in: id); return }
        let spoken = result.speechSeconds
        // Computer output can arrive after its echo on the microphone, so give it
        // a moment to land before deciding the line is the user's own.
        let key = UUID()
        heldSegments[key] = Task { [weak self] in
            try? await Task.sleep(for: MicrophoneEcho.hold)
            self?.keep(segment, in: id, spoken: spoken)
            self?.heldSegments[key] = nil
        }
    }

    private func keep(_ segment: TranscriptSegment, in id: String, spoken: Double? = nil) {
        var changed = false
        var added = false
        store.updateSession(id) { session in
            guard session.deletedAt == nil, !MicrophoneEcho.matches(segment, in: session.transcript.suffix(12)) else { return }
            if let index = session.transcript.firstIndex(where: { $0.id == segment.id }) {
                if session.transcript[index] != segment {
                    session.transcript[index] = segment
                    changed = true
                    syncedSegments.remove(segment.id)
                }
            } else {
                session.transcript.append(segment)
                changed = true
                added = true
            }
        }
        if added, let spoken, let title = store.session(id)?.title, PracticeSession.isPractice(title) {
            store.update {
                var timing = $0.speechTimings?[id] ?? SpeechTiming()
                timing.seconds += spoken
                timing.words += PracticeReview.words(segment.text).count
                $0.speechTimings = ($0.speechTimings ?? [:]).merging([id: timing]) { $1 }
            }
        }
        if changed {
            // Sent first, so an answer is written with these words in its context.
            Task {
                await flush(id)
                if added { consider(segment, in: id) }
            }
        }
    }

    private func offset(_ id: String, _ at: String) -> String {
        guard let session = store.session(id), let start = ISO.date(session.startedAt), let time = ISO.date(at) else {
            return clock(snapshot.elapsedSeconds)
        }
        return clock(max(0, Int(time.timeIntervalSince(start))))
    }

    private func transcriptionFailed(_ failure: TranscriptionFailure, _ id: String, _ expected: Int) {
        guard isCurrent(id, expected), [.listening, .connecting].contains(snapshot.lifecycle) else { return }
        if !failure.permanent && !failure.exhausted {
            let attempt = max(1, failure.attempt ?? 1)
            set {
                $0.connection = .reconnecting; $0.audio = .unavailable
                $0.recoveryAttempt = attempt; $0.recoveryMaxAttempts = 5
                $0.error = "Expo is reconnecting to transcription (\(attempt)/5)…"
            }
            return
        }
        let message = failure.permanent
            ? "Expo could not keep transcription connected. Your session is still open and its history is preserved. Check your settings, then choose Retry listening."
            : "Transcription dropped. Your history is preserved and Expo is reconnecting automatically."
        Task {
            await stopCapture()
            guard isCurrent(id, expected) else { return }
            set { $0.connection = .offline; $0.audio = .unavailable; $0.error = message; $0.recoveryAttempt = nil }
            announceOutage(message)
            if !failure.permanent { recoverAutomatically(id) }
        }
    }

    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard snapshot.lifecycle == .listening, let id = snapshot.sessionId else { return }
        snapshot.elapsedSeconds += 1
        if snapshot.elapsedSeconds % 10 == 0 {
            let elapsed = snapshot.elapsedSeconds
            store.updateSession(id) { $0.durationSeconds = elapsed }
        }
        guard let health = audio.health, !recovering, snapshot.recoveryAttempt == nil else { return }
        audio.reviveMicrophoneIfNeeded()
        if audio.stalled {
            // The output device changed or capture stopped: rebuild it.
            recovering = true
            Task { await recoverAudio(id) }
        } else if store.state.settings.warnOnSilence && health.secondsSinceSound > 45 {
            if snapshot.audio == .ready { set { $0.audio = .silent } }
        } else if snapshot.audio == .silent {
            set { $0.audio = .ready }
        }
    }

    private func recoverAudio(_ id: String) async {
        defer { recovering = false }
        let expected = generation
        let current = { self.isCurrent(id, expected) && self.snapshot.lifecycle == .listening }
        audio.stop()
        level = 0
        var permanent = false
        let outcome = await Recovery.run(
            shouldContinue: current,
            isPermanent: { permanent = ($0 as? AudioCaptureError)?.permanent == true; return permanent },
            onAttempt: { attempt, total in
                set {
                    $0.audio = .unavailable; $0.recoveryAttempt = attempt; $0.recoveryMaxAttempts = total
                    $0.error = "Expo is reconnecting audio (\(attempt)/\(total))…"
                }
            },
            operation: {
                capturingMicrophone = try await audio.start(settings: store.state.settings) { [weak self] in self?.transcription.send($0) }
                // Started is not enough: a microphone has to keep delivering.
                try await Task.sleep(for: .seconds(2))
                guard current() else { return }
                guard audio.microphoneDelivering else {
                    audio.stop()
                    level = 0
                    throw AudioCaptureError(message: "No audio is arriving from this device.")
                }
            }
        )
        switch outcome {
        case .restored:
            set { $0.audio = .ready; $0.error = nil; $0.recoveryAttempt = nil; $0.recoveryMaxAttempts = nil }
        case .abandoned:
            // A pause or end during an attempt must not leave capture running.
            if isCurrent(id, expected), snapshot.lifecycle != .listening { audio.stop() }
        case .failed(let reason):
            audio.stop()
            level = 0
            let message = "Expo could not restore audio. Your session is still open and its history is preserved. \(reason) "
                + (permanent ? "Then choose Retry listening." : "Expo keeps trying automatically.")
            set { $0.audio = .unavailable; $0.error = message; $0.recoveryAttempt = nil; $0.recoveryMaxAttempts = nil }
            announceOutage(message)
            if !permanent { recoverAutomatically(id) }
        }
    }

    // MARK: Realtime

    private func startRealtime(_ id: String) {
        realtime.start(sessionId: id) { [weak self] event in
            self?.handle(event)
        } onState: { [weak self] state in
            guard let self, self.snapshot.sessionId == id, self.snapshot.recoveryAttempt == nil else { return }
            self.set { $0.connection = state }
        }
    }

    private func handle(_ event: RealtimeEvent) {
        if event.type.hasPrefix("suggestion.") { apply(event) }
        // Interim text and deltas are already handled; refresh on durable changes.
        guard !["suggestion.delta", "assistant.delta", "transcript.interim", "presence.changed"].contains(event.type) else { return }
        if event.type == "session.notes.updated" { notesRefreshWanted = true }
        scheduleRefresh(event.sessionId)
    }

    private func scheduleRefresh(_ id: String) {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled else { return }
            let wantsNotes = self.notesRefreshWanted
            self.notesRefreshWanted = false
            await self.refresh(id, notes: wantsNotes)
            self.refreshTask = nil
        }
    }

    private func refresh(_ id: String, notes wantsNotes: Bool) async {
        guard await backend.isAuthenticated else { return }
        do {
            let detail = try await backend.sessionDetail(id)
            let notes = wantsNotes ? try? await backend.latestNotes(id) : nil
            guard let current = store.session(id) else { return }
            var merged = detail.merged(into: current, notes: notes)
            // The client owns the end state until the backend confirms it.
            if current.status == "processing" && merged.status == "active" { merged.status = "processing" }
            store.upsert(merged)
            if let notes, notes.status != "pending", snapshot.sessionId == nil { realtime.stop() }
        } catch {
            if snapshot.sessionId == id { set { $0.connection = .reconnecting } }
        }
    }

    private func apply(_ event: RealtimeEvent) {
        let data = event.payload
        guard let runId = data.runId, let version = data.contextVersion ?? event.contextVersion else { return }
        if event.type == "suggestion.failed", let message = data.message { onError(BackendError(message, code: data.code)) }
        store.updateSession(event.sessionId) { session in
            guard let index = session.liveSuggestions.firstIndex(where: { $0.id == runId }) else {
                guard event.type == "suggestion.started" else { return }
                session.liveSuggestions.append(LiveSuggestion(
                    id: runId, sessionId: event.sessionId, trigger: "automatic", sourceTurnId: data.sourceTurnId,
                    contextVersion: version, reason: data.reason, status: "started", text: data.text ?? "",
                    offset: data.offset ?? 0, createdAt: ISO.now(), updatedAt: ISO.now()
                ))
                return
            }
            var item = session.liveSuggestions[index]
            guard version >= item.contextVersion else { return }
            switch event.type {
            case "suggestion.delta":
                guard version == item.contextVersion else { return }
                item.status = "streaming"
                if let text = data.text { item.text = text } else { item.text += data.delta ?? "" }
            case "suggestion.completed":
                item.status = "completed"
                if let text = data.text { item.text = text }
            case "suggestion.failed":
                item.status = "failed"
                item.errorCode = data.code
                item.errorMessage = data.message
            case "suggestion.superseded":
                item.status = "superseded"
            default:
                item.status = "started"
            }
            item.offset = data.offset ?? item.text.utf16.count
            item.updatedAt = ISO.now()
            session.liveSuggestions[index] = item
        }
    }

    // MARK: Questions

    /// Asks in a task that `stopAnswer` can cancel.
    func submit(_ question: String, label: String? = nil, withScreen: Bool = false, sourceID: String? = nil) {
        guard !isAsking else { return }
        askTask = Task { await ask(question, label: label, withScreen: withScreen, sourceID: sourceID) }
    }

    func stopAnswer() { askTask?.cancel() }

    /// Captures the screen and answers what is on it, with nothing to type.
    /// It takes over from an answer being written.
    func captureAndAnswer(sourceID: String? = nil, source: String = "the entire screen") {
        let previous = askTask
        previous?.cancel()
        askTask = Task {
            await previous?.value
            await ask(ScreenAnswer.request, label: ScreenAnswer.label, withScreen: true, sourceID: sourceID,
                      format: ScreenAnswer.format(plainEnglish: store.state.settings.plainEnglish), noteSource: source)
        }
    }

    /// Records in the transcript that the screen was captured and answered.
    private func noteCapture(_ answer: String, source: String, in id: String) {
        let segment = TranscriptSegment(
            id: UUID().uuidString.lowercased(), at: clock(snapshot.elapsedSeconds), speaker: ScreenAnswer.speaker,
            text: ScreenAnswer.transcriptNote(source: source, answer: answer), confidence: "high")
        store.updateSession(id) { $0.transcript.append(segment) }
        Task { await flush(id) }
    }

    /// A stopped answer keeps whatever had already arrived.
    private func keepStopped(_ question: String, in id: String) {
        let partial = streamedText.trimmed
        if !partial.isEmpty {
            record(AssistantMessage(id: UUID().uuidString.lowercased(), question: question, summary: partial,
                                    references: [], confidence: "low", createdAt: ISO.now()), in: id)
        }
        pendingQuestion = nil
        streamedText = ""
    }

    /// `label` is what the conversation shows when the sent text is a long follow-up.
    func ask(_ question: String, label: String? = nil, withScreen: Bool = false, sourceID: String? = nil,
             format: String? = nil, noteSource: String? = nil) async {
        let question = question.trimmed
        guard !question.isEmpty else {
            if withScreen { onError(BackendError("Enter a question before asking with screen context.")) }
            return
        }
        guard !isAsking else { return }
        do {
            guard hasConsent else { throw BackendError("Transcript consent is required before using Assist.") }
            guard question.count <= 1_000 else { throw BackendError("Enter a question under 1,000 characters.") }
            guard let id = store.state.activeSessionId, isBackendID(id), await backend.isAuthenticated else {
                throw BackendError("Sign in to Expo and start an Assist session before asking the assistant.")
            }
            isAsking = true
            pendingQuestion = label ?? question
            pendingScreen = withScreen
            streamedText = ""
            defer { isAsking = false; pendingScreen = false }
            let image = withScreen ? try await ScreenContextCapture.capture(sourceID: sourceID) : nil
            // The chosen style shapes questions; named follow-ups say their own.
            let format = format ?? (label == nil ? answerFormat : nil)
            var answer = try await backend.ask(sessionId: id, question: question, screenImage: image, format: format) { [weak self] delta in
                await self?.appendDelta(delta, session: id)
            }
            if let label { answer.question = label }
            if let image { screenshots[answer.id] = image }
            record(answer, in: id)
            if let noteSource { noteCapture(answer.summary, source: noteSource, in: id) }
            pendingQuestion = nil
            streamedText = ""
        } catch where Task.isCancelled {
            if let id = store.state.activeSessionId { keepStopped(label ?? question, in: id) }
        } catch let error as BackendError {
            pendingQuestion = nil
            streamedText = ""
            onError(error)
        } catch {
            pendingQuestion = nil
            onError(BackendError(error.localizedDescription))
        }
    }

    private var answerFormat: String? {
        let settings = store.state.settings
        return settings.answerStyle.instruction(plainEnglish: settings.plainEnglish)
    }

    private func appendDelta(_ delta: String, session id: String) {
        guard store.state.activeSessionId == id else { return }
        streamedText += delta
    }

    /// "What should I say?" uses live suggestions, which know who spoke last.
    func suggest() async {
        guard !isAsking else { return }
        guard let id = store.state.activeSessionId, isBackendID(id), await backend.isAuthenticated else {
            onError(BackendError("Start a signed-in Assist session before requesting a live suggestion."))
            return
        }
        isAsking = true
        do {
            let instruction = answerFormat.map { "Suggest the best response for the user to say next in the meeting. \($0)" }
            upsert(try await backend.createSuggestion(sessionId: id, instruction: instruction))
            isAsking = false
        } catch let error as BackendError where error.isPaywall {
            isAsking = false
            onError(error)
        } catch {
            isAsking = false
            await ask("What should I say?")
        }
    }

    func retrySuggestion(_ suggestionID: String) async {
        do { upsert(try await backend.resumeSuggestion(suggestionID)) }
        catch let error as BackendError { onError(error) }
        catch {}
    }

    private func upsert(_ suggestion: LiveSuggestion) {
        store.updateSession(suggestion.sessionId) { session in
            if let index = session.liveSuggestions.firstIndex(where: { $0.id == suggestion.id }) {
                // A streamed event may already be ahead of this response.
                let existing = session.liveSuggestions[index]
                if suggestion.offset >= existing.offset || suggestion.contextVersion > existing.contextVersion {
                    session.liveSuggestions[index] = suggestion
                }
            } else {
                session.liveSuggestions.append(suggestion)
            }
        }
    }

    /// Stored locally first; the remote write is idempotent by message id.
    private func record(_ answer: AssistantMessage, in id: String) {
        store.updateSession(id) { session in
            if !session.assistantMessages.contains(where: { $0.id == answer.id }) {
                session.assistantMessages.append(answer)
            }
        }
        pendingMessageSessions.insert(id)
        startSync()
        Task { await flush(id) }
    }

    // MARK: Sync queue

    private func startSync() {
        guard syncTask == nil else { return }
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { return }
                if await !self.syncPending() { self.syncTask = nil; return }
            }
        }
    }

    /// Returns false once nothing is left to send.
    private func syncPending() async -> Bool {
        if let ended = store.state.sessions.first(where: {
            $0.status == "processing" && $0.endedAt != nil && isBackendID($0.id) && $0.notesStatus == "pending"
        }) {
            await finalize(ended.id)
        }
        if let id = snapshot.sessionId { await flush(id) }
        for id in pendingMessageSessions where id != snapshot.sessionId { await flush(id) }
        return snapshot.sessionId != nil || !pendingMessageSessions.isEmpty
            || store.state.sessions.contains { $0.status == "processing" && $0.notesStatus == "pending" }
    }

    @discardableResult
    private func flush(_ id: String) async -> Bool {
        guard await backend.isAuthenticated, isBackendID(id) else { return false }
        guard !flushing else { return false }
        guard let session = store.session(id) else { pendingMessageSessions.remove(id); return true }
        guard hasConsent else { return false }
        flushing = true
        defer { flushing = false }
        do {
            let segments = session.transcript.filter { !syncedSegments.contains($0.id) }
            for start in stride(from: 0, to: segments.count, by: 200) {
                let batch = Array(segments[start..<min(start + 200, segments.count)])
                try await backend.appendSegments(id, batch)
                syncedSegments.formUnion(batch.map(\.id))
            }
            for message in session.assistantMessages where !syncedMessages.contains(message.id) {
                _ = try await backend.appendAssistantMessage(id, message)
                syncedMessages.insert(message.id)
            }
            pendingMessageSessions.remove(id)
            return true
        } catch let error as BackendError {
            // A rejected record will never succeed; stop retrying it for old sessions.
            if let status = error.status, [400, 403, 404, 409].contains(status), id != snapshot.sessionId {
                pendingMessageSessions.remove(id)
            }
            return false
        } catch {
            return false
        }
    }

    private func finalize(_ id: String) async {
        // Held microphone lines belong in the notes.
        for task in Array(heldSegments.values) { await task.value }
        guard !finalizing, await backend.isAuthenticated, let session = store.session(id),
              let endedAt = session.endedAt else { return }
        finalizing = true
        guard await flush(id) else { finalizing = false; return }
        do {
            // The email choice goes with completion, so it is in place before
            // the notes are written even if it was changed while offline.
            _ = try await backend.updateSession(id, .init(status: "complete", endedAt: endedAt, durationSeconds: session.durationSeconds,
                                                          emailNotes: session.emailNotes))
        } catch let error as BackendError where !error.isTransient {
            store.updateSession(id) { $0.status = "complete"; $0.notesStatus = "failed"; $0.notesError = error.message }
            finalizing = false
            return
        } catch {
            finalizing = false
            return
        }
        store.updateSession(id) { $0.status = "complete" }
        finalizing = false
        await prepareNotes(id)
    }

    private func prepareNotes(_ id: String) async {
        do {
            do { _ = try await backend.latestNotes(id) }
            catch let error as BackendError where error.status == 404 {
                guard hasConsent else { return }
                try await backend.requestNotes(id)
            }
            let notes = try await backend.waitForNotes(id)
            store.updateSession(id) { notes.apply(to: &$0) }
            // The notes step names the session; pick the new name up with them.
            if notes.status == "ready", let detail = try? await backend.sessionOverview(id) {
                store.updateSession(id) { $0.title = detail.title }
            }
        } catch {
            store.updateSession(id) { $0.notesStatus = "failed"; $0.notesError = error.localizedDescription }
        }
        if snapshot.sessionId == nil { realtime.stop() }
    }
}
