import Foundation

struct BackendError: LocalizedError, Sendable {
    var message: String
    var code: String?
    var status: Int?
    var runID: String?
    var partialText: String?

    init(_ message: String, code: String? = nil, status: Int? = nil) {
        self.message = message
        self.code = code
        self.status = status
    }

    var errorDescription: String? { message }
    /// The service could not be reached or is failing, so local data should be used.
    var isTransient: Bool { code == "BACKEND_UNAVAILABLE" || (status ?? 0) >= 500 }
    var isPaywall: Bool { message == Self.paywallPlan || message == Self.paywallQuota }

    static let paywallPlan = "This feature is not included in your Expo plan. Upgrade to use it."
    static let paywallQuota = "You have used your Expo allowance for this period. Upgrade or wait for it to reset."
    static let invalidResponse = BackendError("Expo received an unexpected response. Please try again.", code: "INVALID_BACKEND_RESPONSE")
}

// MARK: Responses

struct AuthSession: Decodable, Sendable {
    var token: String
    var expiresAt: String
    var user: UserAccount
}

enum AuthResult: Sendable {
    case signedIn(AuthSession)
    case verificationRequired(email: String)
}

struct RemoteSession: Decodable, Sendable {
    var id: String
    var title: String
    var status: String
    var startedAt: String
    var endedAt: String?
    var durationSeconds: Int?
    var notes: SessionNotes?
    var deletedAt: String?
    var contextVersion: Int?
    var profileContextEnabled: Bool?
    var transcript: [TranscriptSegment]?
    var assistantMessages: [AssistantMessage]?
    var liveSuggestions: [LiveSuggestion]?

    /// Overlays server truth on the cached copy, keeping anything not yet synced.
    func merged(into local: ExpoSession?, notes detail: NotesDetail? = nil) -> ExpoSession {
        var session = local ?? ExpoSession(id: id, title: title, startedAt: startedAt, status: status)
        session.title = title
        session.status = status
        session.startedAt = startedAt
        session.durationSeconds = durationSeconds ?? session.durationSeconds
        if let endedAt { session.endedAt = endedAt }
        session.deletedAt = deletedAt ?? session.deletedAt
        session.contextVersion = contextVersion ?? session.contextVersion
        session.profileContextEnabled = profileContextEnabled ?? session.profileContextEnabled
        if let notes { session.notes = notes; session.notesStatus = "ready" }
        if let transcript { session.transcript = Self.merge(session.transcript, transcript) }
        if let assistantMessages { session.assistantMessages = Self.merge(session.assistantMessages, assistantMessages) }
        if let liveSuggestions {
            session.liveSuggestions = Self.merge(session.liveSuggestions, liveSuggestions)
                .sorted { $0.createdAt < $1.createdAt }
        }
        detail?.apply(to: &session)
        return session
    }

    static func merge<T: Identifiable>(_ local: [T], _ remote: [T]) -> [T] {
        let ids = Set(remote.map(\.id))
        return remote + local.filter { !ids.contains($0.id) }
    }
}

struct ResultPage<Item: Decodable & Sendable>: Decodable, Sendable {
    var items: [Item]
    var nextCursor: String?
}

struct SearchMatch: Decodable, Sendable, Hashable {
    var source: String
    var label: String
    var snippet: String
}

struct SearchResult: Decodable, Sendable {
    var session: RemoteSession
    var matches: [SearchMatch]
    var matchCount: Int
}

struct NotesDetail: Decodable, Sendable {
    var id: String
    var version: Int
    var status: String
    var error: String?
    var content: SessionNotes?

    func apply(to session: inout ExpoSession) {
        if status == "ready", let content {
            session.notes = content
            session.notesStatus = "ready"
            session.notesError = nil
        } else if status == "failed" {
            session.notesStatus = "failed"
            session.notesError = error ?? "Expo could not prepare these notes."
        } else {
            session.notesStatus = "pending"
        }
    }
}

struct AssistantRun: Decodable, Sendable {
    var id: String
    var status: String
    var text: String
    var offset: Int
    var errorCode: String?
    var errorMessage: String?
}

struct DraftResponse: Decodable, Sendable {
    var step: Int
    var profile: ProfessionalProfile
    var cvUploadId: String?
    var cvName: String?
    var cvStatus: String?
    var revision: Int
    var updatedAt: String
}

struct ProfileResponse: Decodable, Sendable {
    var profile: ProfessionalProfile
    var sourceUploadId: String?
}

struct CvUpload: Decodable, Sendable {
    var id: String
    var name: String
    var size: Int
    var type: String
    var status: String
    var errorCode: String?
    var profile: ProfessionalProfile?
    var uploadedAt: String

    var isFinished: Bool { ["ready", "failed", "rejected"].contains(status) }
}

private struct Ignored: Decodable, Sendable { init(from decoder: Decoder) throws {} }

/// Turns a UTF-8 byte stream into text deltas, skipping text already shown.
private struct StreamDecoder {
    var text: String
    var remaining: Int
    private var buffer = Data()

    init(text: String, remaining: Int) {
        self.text = text
        self.remaining = remaining
    }

    mutating func append(_ byte: UInt8) { buffer.append(byte) }

    mutating func flush() -> String? {
        guard !buffer.isEmpty, var delta = String(data: buffer, encoding: .utf8) else { return nil }
        buffer.removeAll(keepingCapacity: true)
        if remaining > 0 {
            let units = Array(delta.utf16)
            let dropped = min(remaining, units.count)
            remaining -= dropped
            delta = String(decoding: units.dropFirst(dropped), as: UTF16.self)
        }
        guard !delta.isEmpty else { return nil }
        text += delta
        return delta
    }
}

// MARK: Client

actor BackendClient {
    private enum Context { case auth, cv, general }

    nonisolated let config: AppConfig
    private let session: URLSession
    private(set) var userToken: String?
    private var expiredHandler: (@Sendable () -> Void)?

    private static let timeout: TimeInterval = 30
    private static let transcriptConsent = ["x-expo-transcript-consent": "granted"]
    private static let cvConsent = ["x-expo-cv-consent": "granted"]
    private static let streamUnavailableText = "Expo's AI is not responding right now. Please try again in a moment."
    private static let streamErrorText = "Expo could not finish this response. Please try again."
    private static let askUnreachable = "Expo can't connect right now. Check your internet connection and ask again."

    init(config: AppConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    var isAuthenticated: Bool { config.isBackendConfigured && userToken != nil }

    func setUserToken(_ token: String?) { userToken = token?.trimmed.nonEmpty }
    func onSessionExpired(_ handler: @escaping @Sendable () -> Void) { expiredHandler = handler }

    /// Headers shared by HTTP requests and both WebSockets.
    func authHeaders() -> [String: String] {
        var headers = ["x-expo-client": "desktop"]
        if let key = config.apiKey { headers["Authorization"] = "Bearer \(key)" }
        if let userToken { headers["x-expo-user-session"] = userToken }
        return headers
    }

    nonisolated func socketURL(_ path: String) -> URL {
        var parts = URLComponents(url: config.backendURL, resolvingAgainstBaseURL: false)!
        parts.scheme = parts.scheme == "https" ? "wss" : "ws"
        parts.path += path
        return parts.url!
    }

    // MARK: Auth

    func register(firstName: String, lastName: String, email: String, password: String) async throws -> AuthResult {
        try await authResult("/auth/register", ["firstName": firstName, "lastName": lastName, "email": email, "password": password])
    }

    func signIn(email: String, password: String) async throws -> AuthResult {
        try await authResult("/auth/login", ["email": email, "password": password])
    }

    private func authResult(_ path: String, _ body: [String: String]) async throws -> AuthResult {
        let data = try await raw(path, method: "POST", body: try json(body), context: .auth)
        struct Pending: Decodable { var verificationRequired: Bool; var email: String }
        if let pending = try? JSONDecoder().decode(Pending.self, from: data), pending.verificationRequired {
            return .verificationRequired(email: pending.email)
        }
        return .signedIn(try decode(data))
    }

    func verifyEmail(email: String, code: String) async throws -> AuthSession {
        try await request("/auth/verify-email", method: "POST", body: try json(["email": email, "code": code]), context: .auth)
    }

    func resendCode(email: String) async throws {
        let _: Ignored? = try await request("/auth/resend-code", method: "POST", body: try json(["email": email]), context: .auth)
    }

    func requestPasswordReset(email: String) async throws -> String {
        struct Response: Decodable { var message: String }
        let response: Response = try await request("/auth/password-reset/request", method: "POST", body: try json(["email": email]), context: .auth)
        return response.message
    }

    func verifyPasswordReset(email: String, code: String) async throws -> (token: String, expiresAt: String) {
        struct Response: Decodable { var resetToken: String; var expiresAt: String }
        let response: Response = try await request("/auth/password-reset/verify", method: "POST", body: try json(["email": email, "code": code]), context: .auth)
        return (response.resetToken, response.expiresAt)
    }

    func completePasswordReset(token: String, password: String) async throws {
        let _: Ignored? = try await request("/auth/password-reset/complete", method: "POST", body: try json(["resetToken": token, "password": password]), context: .auth)
    }

    func currentUser() async throws -> UserAccount {
        try await request("/auth/me", context: .auth)
    }

    func logout() async throws {
        guard userToken != nil else { return }
        let _: Ignored? = try await request("/auth/logout", method: "POST", context: .auth)
    }

    // MARK: Onboarding, profile, settings, billing

    func onboardingDraft() async throws -> DraftResponse? { try await request("/onboarding/draft") }

    func saveOnboardingDraft(_ draft: OnboardingDraft) async throws -> DraftResponse {
        struct Body: Encodable {
            var step: Int; var profile: ProfessionalProfile
            var cvUploadId: String?; var cvName: String?; var cvStatus: String?
        }
        let body = Body(step: draft.step, profile: draft.profile, cvUploadId: draft.cvUploadId, cvName: draft.cvName, cvStatus: draft.cvStatus)
        return try await request("/onboarding/draft", method: "PUT", body: try json(body))
    }

    func clearOnboardingDraft() async throws {
        let _: Ignored? = try await request("/onboarding/draft", method: "DELETE")
    }

    func profile() async throws -> ProfileResponse? { try await request("/profile") }

    func saveProfile(_ profile: ProfessionalProfile, sourceUploadId: String?) async throws {
        struct Body: Encodable { var profile: ProfessionalProfile; var sourceUploadId: String? }
        let _: Ignored? = try await request("/profile", method: "PUT", body: try json(Body(profile: profile, sourceUploadId: sourceUploadId)))
    }

    /// True when the admin or plan setting hides Expo from screen capture.
    func contentProtection() async throws -> Bool? {
        struct Response: Decodable { var contentProtectionEnabled: Bool? }
        let response: Response = try await request("/settings/content-protection")
        return response.contentProtectionEnabled
    }

    func billing() async throws -> BillingSummary { try await request("/billing/me") }

    func createCheckout(plan: String, interval: String) async throws -> (url: URL, checkoutId: String) {
        struct Response: Decodable { var url: String; var checkoutId: String }
        let response: Response = try await request("/billing/checkout", method: "POST", body: try json(["plan": plan, "interval": interval]))
        guard let url = URL(string: response.url), url.scheme == "https" || url.scheme == "http" else {
            throw BackendError("Expo could not start checkout. Try again shortly.")
        }
        return (url, response.checkoutId)
    }

    /// Switches plan without payment. A development server alone allows it.
    func activateTestPlan(_ plan: String, interval: String) async throws {
        let _: Ignored? = try await request("/billing/test-activate", method: "POST", body: try json(["plan": plan, "interval": interval]))
    }

    func checkoutPaid(_ checkoutId: String) async throws -> Bool {
        struct Response: Decodable { var status: String }
        let response: Response = try await request("/billing/sync", method: "POST", body: try json(["checkoutId": checkoutId]))
        return response.status == "paid"
    }

    func isReady() async -> Bool {
        var request = URLRequest(url: url("/health/ready"), timeoutInterval: Self.timeout)
        request.httpMethod = "GET"
        guard let (_, response) = try? await session.data(for: request) else { return false }
        return ((response as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2
    }

    func assistantProviderDetail() async -> (ready: Bool, detail: String) {
        struct Provider: Decodable { var provider: String; var model: String; var isDefault: Bool }
        do {
            let providers: [Provider] = try await request("/ai/providers")
            guard let chosen = providers.first(where: \.isDefault) ?? providers.first else {
                return (false, "No enabled chat provider is configured in the admin system.")
            }
            return (true, "\(chosen.provider) · \(chosen.model)")
        } catch { return (false, error.localizedDescription) }
    }

    func transcriptionProviderDetail() async -> (ready: Bool, detail: String) {
        struct Status: Decodable { var state: String; var detail: String }
        do {
            let status: Status = try await request("/transcription/status")
            return (status.state == "ready", status.detail)
        } catch { return (false, error.localizedDescription) }
    }

    // MARK: CV

    func uploadCv(file: URL, idempotencyKey: String) async throws -> CvUpload {
        guard let bytes = try? Data(contentsOf: file) else {
            throw BackendError("Expo could not find the selected CV on this computer. Choose the file again to continue.", code: "LOCAL_FILE_UNAVAILABLE")
        }
        let name = file.lastPathComponent
        if let problem = CvRules.problem(name: name, size: bytes.count) {
            throw BackendError(problem, code: "INVALID_FILE")
        }
        let type = name.lowercased().hasSuffix(".pdf")
            ? "application/pdf"
            : "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        let boundary = "expo-\(UUID().uuidString)"
        let safeName = name.replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\nContent-Type: \(type)\r\n\r\n".utf8))
        body.append(bytes)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var headers = Self.cvConsent
        headers["Idempotency-Key"] = idempotencyKey
        return try await request("/files", method: "POST", body: body, contentType: "multipart/form-data; boundary=\(boundary)", headers: headers, context: .cv)
    }

    func cvUpload(_ id: String) async throws -> CvUpload {
        try await request("/files/\(try safeID(id))", context: .cv)
    }

    func reprocessCv(_ id: String) async throws -> CvUpload {
        try await request("/files/\(try safeID(id))/reprocess", method: "POST", headers: Self.cvConsent, context: .cv)
    }

    func deleteCv(_ id: String) async throws {
        let _: Ignored? = try await request("/files/\(try safeID(id))", method: "DELETE", context: .cv)
    }

    func waitForCv(_ initial: CvUpload) async throws -> CvUpload {
        var current = initial
        let deadline = Date().addingTimeInterval(120)
        while !current.isFinished {
            guard Date() < deadline else {
                throw BackendError("CV processing is taking longer than expected. Please check again later.", code: "PROCESSING_TIMEOUT")
            }
            try await Task.sleep(for: .seconds(1))
            current = try await cvUpload(current.id)
        }
        return current
    }

    // MARK: Sessions

    func createSession(title: String, startedAt: String, profileContextEnabled: Bool, prepNotes: String?) async throws -> RemoteSession {
        struct Body: Encodable {
            var title: String; var startedAt: String; var memory: [String: String]; var profileContextEnabled: Bool; var prepNotes: String?
        }
        let body = Body(title: title, startedAt: startedAt, memory: ["memoryMode": "current_only"], profileContextEnabled: profileContextEnabled, prepNotes: prepNotes)
        return try await request("/sessions", method: "POST", body: try json(body))
    }

    func sessions(trash: Bool, cursor: String? = nil, limit: Int = 25) async throws -> ResultPage<RemoteSession> {
        try await request(trash ? "/sessions/trash" : "/sessions", query: ["limit": "\(limit)", "cursor": cursor])
    }

    func searchSessions(_ text: String, trash: Bool) async throws -> ResultPage<SearchResult> {
        try await request("/sessions/search", query: ["q": text, "limit": "25", "trash": trash ? "true" : nil])
    }

    func sessionOverview(_ id: String) async throws -> RemoteSession {
        try await request("/sessions/\(try safeID(id))/overview")
    }

    func sessionDetail(_ id: String) async throws -> RemoteSession {
        try await request("/sessions/\(try safeID(id))")
    }

    func transcript(_ id: String, before: String? = nil) async throws -> ResultPage<TranscriptSegment> {
        try await request("/sessions/\(try safeID(id))/transcript", query: ["limit": "200", "before": before])
    }

    struct SessionPatch: Encodable, Sendable {
        var title: String?
        var status: String?
        var endedAt: String?
        var durationSeconds: Int?
        var notes: SessionNotes?
        var profileContextEnabled: Bool?
    }

    func updateSession(_ id: String, _ patch: SessionPatch) async throws -> RemoteSession {
        try await request("/sessions/\(try safeID(id))", method: "PATCH", body: try json(patch))
    }

    func appendSegments(_ id: String, _ segments: [TranscriptSegment]) async throws {
        let _: Ignored? = try await request("/sessions/\(try safeID(id))/segments", method: "POST", body: try json(["segments": segments]), headers: Self.transcriptConsent)
    }

    func appendAssistantMessage(_ id: String, _ message: AssistantMessage) async throws -> AssistantMessage {
        try await request("/sessions/\(try safeID(id))/assistant-messages", method: "POST", body: try json(message), headers: Self.transcriptConsent)
    }

    func deleteSession(_ id: String) async throws {
        let _: Ignored? = try await request("/sessions/\(try safeID(id))", method: "DELETE")
    }

    func restoreSession(_ id: String) async throws -> RemoteSession {
        try await request("/sessions/\(try safeID(id))/restore", method: "POST")
    }

    func setAiControls(_ id: String, paused: Bool, autoAnswer: Bool? = nil) async throws {
        struct Body: Encodable { var paused: Bool; var autoAnswer: Bool? }
        let _: Ignored? = try await request("/sessions/\(try safeID(id))/ai-controls", method: "PATCH", body: try json(Body(paused: paused, autoAnswer: autoAnswer)))
    }

    // MARK: Notes

    func requestNotes(_ id: String) async throws {
        let _: Ignored? = try await request("/sessions/\(try safeID(id))/notes", method: "POST", headers: Self.transcriptConsent)
    }

    func latestNotes(_ id: String) async throws -> NotesDetail {
        try await request("/sessions/\(try safeID(id))/notes/latest")
    }

    func waitForNotes(_ id: String) async throws -> NotesDetail {
        let deadline = Date().addingTimeInterval(120)
        var current = try await latestNotes(id)
        while current.status == "pending" {
            guard Date() < deadline else {
                throw BackendError("Session notes are taking longer than expected. Please check again later.", code: "NOTES_TIMEOUT")
            }
            try await Task.sleep(for: .seconds(1))
            current = try await latestNotes(id)
        }
        return current
    }

    // MARK: Assistant

    func createSuggestion(sessionId: String, instruction: String?) async throws -> LiveSuggestion {
        struct Body: Encodable { var sessionId: String; var trigger = "manual"; var instruction: String?; var clientRequestId: String }
        let body = Body(sessionId: sessionId, instruction: instruction?.trimmed.nonEmpty, clientRequestId: UUID().uuidString.lowercased())
        return try await request("/assistant/suggestions", method: "POST", body: try json(body))
    }

    func resumeSuggestion(_ id: String) async throws -> LiveSuggestion {
        try await request("/assistant/suggestions/\(try safeID(id))/resume", method: "POST")
    }

    private func assistantRun(_ id: String) async throws -> AssistantRun {
        try await request("/assistant/runs/\(try safeID(id))")
    }

    /// Streams an answer, resuming from the backend's saved run if the connection drops.
    func ask(
        sessionId: String,
        question: String,
        screenImage: String?,
        onDelta: @escaping @Sendable (String) async -> Void
    ) async throws -> AssistantMessage {
        struct Screen: Encodable { var imageDataUrl: String }
        struct Body: Encodable { var question: String; var sessionId: String; var screenContext: Screen? }
        let body = try json(Body(question: question, sessionId: sessionId, screenContext: screenImage.map(Screen.init)))
        let text: String
        do {
            text = try await stream("/assistant/ask/stream", body: body, onDelta: onDelta)
        } catch let error as BackendError where error.code == "BACKEND_UNAVAILABLE" && error.runID != nil {
            text = try await resume(runID: error.runID!, from: error.partialText ?? "", onDelta: onDelta)
        }
        return AssistantMessage(
            id: UUID().uuidString.lowercased(), question: question, summary: text,
            references: [], confidence: "medium", createdAt: ISO.now(),
            screenContextUsed: screenImage == nil ? nil : true
        )
    }

    private func resume(runID: String, from partial: String, onDelta: @escaping @Sendable (String) async -> Void) async throws -> String {
        var text = partial
        var lastError = BackendError(Self.askUnreachable, code: "BACKEND_UNAVAILABLE")
        for _ in 0..<3 {
            do {
                let snapshot = try await assistantRun(runID)
                if snapshot.status == "failed" {
                    throw BackendError(snapshot.errorMessage ?? "Expo could not finish the answer. Please try again.", code: snapshot.errorCode, status: 503)
                }
                // Offsets are UTF-16 code units, matching the server.
                guard text.hasPrefix(snapshot.text) || snapshot.text.hasPrefix(text) else {
                    throw BackendError("Expo could not safely resume the interrupted answer. Please retry your question.", code: "ASSISTANT_STREAM_RESUME_CONFLICT")
                }
                let since = min(text.utf16.count, snapshot.offset)
                return try await stream(
                    "/assistant/runs/\(try safeID(runID))/stream?sinceOffset=\(since)",
                    body: nil, initial: text, skip: max(0, text.utf16.count - snapshot.offset), onDelta: onDelta
                )
            } catch let error as BackendError where error.code == "BACKEND_UNAVAILABLE" {
                lastError = error
                text = error.partialText ?? text
            }
        }
        throw lastError
    }

    private func stream(
        _ path: String, body: Data?, initial: String = "", skip: Int = 0,
        onDelta: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        var request = URLRequest(url: url(path), timeoutInterval: Self.timeout)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in authHeaders() { request.setValue(value, forHTTPHeaderField: key) }
        for (key, value) in Self.transcriptConsent { request.setValue(value, forHTTPHeaderField: key) }

        var text = initial
        var runID: String?
        var remaining = skip
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
            runID = http.value(forHTTPHeaderField: "X-Expo-Assistant-Run-Id")
            guard http.statusCode / 100 == 2 else {
                var data = Data()
                for try await byte in bytes { data.append(byte); if data.count > 65_536 { break } }
                throw failure(status: http.statusCode, data: data, path: path, context: .general)
            }

            var decoder = StreamDecoder(text: text, remaining: remaining)
            defer { text = decoder.text; remaining = decoder.remaining }
            var lastFlush = ContinuousClock.now
            for try await byte in bytes {
                decoder.append(byte)
                // Flush on word boundaries (ASCII never splits a character) or every 80 ms.
                if byte == 32 || byte == 10 || ContinuousClock.now - lastFlush > .milliseconds(80) {
                    if let delta = decoder.flush() { await onDelta(delta) }
                    lastFlush = .now
                }
            }
            if let delta = decoder.flush() { await onDelta(delta) }
            text = decoder.text
            remaining = decoder.remaining

            if remaining > 0 {
                throw BackendError("Expo could not safely resume the interrupted answer. Please retry your question.", code: "ASSISTANT_STREAM_RESUME_CONFLICT")
            }
            if let runID {
                let run = try await assistantRun(runID)
                if run.status == "failed" {
                    throw BackendError(run.errorMessage ?? "Expo could not finish the answer. Please try again.", code: run.errorCode, status: 503)
                }
                if run.status != "completed" { throw BackendError(Self.askUnreachable, code: "BACKEND_UNAVAILABLE") }
            }
            if text == Self.streamUnavailableText { throw BackendError("Expo is temporarily unavailable. Please try again shortly.", code: "AI_UNAVAILABLE") }
            if text.hasSuffix(Self.streamErrorText) { throw BackendError("Expo could not finish the answer. Please try again.", code: "AI_STREAM_FAILED") }
            if text.trimmed.isEmpty { throw BackendError("Expo received an empty assistant response. Please try again.", code: "EMPTY_STREAM") }
            return text
        } catch var error as BackendError {
            error.runID = runID ?? error.runID
            error.partialText = text
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            var wrapped = BackendError(Self.askUnreachable, code: "BACKEND_UNAVAILABLE")
            wrapped.runID = runID
            wrapped.partialText = text
            throw wrapped
        }
    }

    // MARK: Transport

    private func safeID(_ id: String) throws -> String {
        guard isBackendID(id) else { throw BackendError("The stored reference is invalid.", code: "INVALID_ID") }
        return id
    }

    private func url(_ path: String, query: [String: String?] = [:]) -> URL {
        var text = config.backendURL.absoluteString + path
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let items = query.sorted { $0.key < $1.key }.compactMap { key, value -> String? in
            guard let value, let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
            return "\(key)=\(encoded)"
        }
        if !items.isEmpty { text += "?" + items.joined(separator: "&") }
        return URL(string: text)!
    }

    private func json<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data.isEmpty ? Data("null".utf8) : data) }
        catch { throw BackendError.invalidResponse }
    }

    private func request<T: Decodable>(
        _ path: String, method: String = "GET", query: [String: String?] = [:], body: Data? = nil,
        contentType: String = "application/json", headers: [String: String] = [:], context: Context = .general
    ) async throws -> T {
        try decode(try await raw(path, method: method, query: query, body: body, contentType: contentType, headers: headers, context: context))
    }

    private func raw(
        _ path: String, method: String = "GET", query: [String: String?] = [:], body: Data? = nil,
        contentType: String = "application/json", headers: [String: String] = [:], context: Context = .general
    ) async throws -> Data {
        var request = URLRequest(url: url(path, query: query), timeoutInterval: Self.timeout)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        for (key, value) in authHeaders().merging(headers, uniquingKeysWith: { $1 }) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let sentToken = userToken
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw BackendError(unreachableMessage(path, context), code: "BACKEND_UNAVAILABLE") }
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        guard http.statusCode / 100 == 2 else {
            // Only expire the session that was actually rejected, not a newer one.
            if http.statusCode == 401, sentToken != nil, sentToken == userToken {
                userToken = nil
                expiredHandler?()
            }
            throw failure(status: http.statusCode, data: data, path: path, context: context)
        }
        return data
    }

    private func failure(status: Int, data: Data, path: String, context: Context) -> BackendError {
        struct Envelope: Decodable { var code: String?; var message: String? }
        let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        let code = envelope?.code
        let message: String
        if context == .auth, let text = envelope?.message { message = text }
        else if status == 401 || code == "UNAUTHENTICATED" {
            message = context == .cv ? "Your session has expired. Sign in again, then upload your CV." : "Your session has expired. Please sign in again."
        } else if status == 400 || code == "VALIDATION_ERROR" {
            message = context == .cv ? "This file can't be used. Choose a PDF or Word document up to 10 MB." : "Some details don't look right. Check them and try again."
        } else if code == "QUOTA_EXCEEDED" { message = BackendError.paywallQuota }
        else if code == "PLAN_REQUIRED" || status == 402 { message = BackendError.paywallPlan }
        else if status == 413 { message = "That screen capture was too large to send. Try capturing a smaller window." }
        else if code == "VISION_UNAVAILABLE" { message = "Screen questions aren't available right now. Ask without the screen instead." }
        else if status == 404 || code == "NOT_FOUND" { message = "We couldn't find that item. It may have been deleted." }
        else if status == 409 || code == "CONFLICT" { message = "This was changed somewhere else. Refresh and try again." }
        else if status == 429 || code == "RATE_LIMITED" { message = "Expo is busy right now. Please wait a moment and try again." }
        else if status == 503 || code == "DEPENDENCY_UNAVAILABLE" { message = "Expo is temporarily unavailable. Please try again shortly." }
        else { message = context == .cv ? "We couldn't process your CV. Please upload it again." : "Something went wrong. Please try again." }
        return BackendError(message, code: code, status: status)
    }

    private func unreachableMessage(_ path: String, _ context: Context) -> String {
        if context == .cv { return "Can't connect right now. Check your internet connection, then upload your CV again." }
        if path.hasPrefix("/sessions") { return "Can't connect right now. Your meeting is saved on this device and will sync when you're back online." }
        return "Can't connect right now. Check your internet connection and try again."
    }
}

enum CvRules {
    static func problem(name: String, size: Int) -> String? {
        let ext = (name as NSString).pathExtension.lowercased()
        if ext != "pdf" && ext != "docx" { return "Expo supports PDF and DOCX files." }
        if size > 10 * 1024 * 1024 { return "Your CV must be 10 MB or smaller." }
        if size <= 0 { return "This file is empty." }
        return nil
    }
}
