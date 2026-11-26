import Foundation

struct TranscriptionResult: Decodable, Sendable {
    var segmentId: String
    var at: String
    var text: String
    var confidence: String
    var isFinal: Bool
    var source: String?
    var channelIndex: Int?
    var sessionId: String?
}

struct TranscriptionFailure: Sendable {
    var message: String
    var attempt: Int?
    var exhausted = false
    var permanent = false
}

/// Streams 48 kHz PCM to the backend transcription gateway.
@MainActor
final class TranscriptionClient {
    private static let maxPendingBytes = 2 * 1024 * 1024
    private static let maxAttempts = 5

    private let backend: BackendClient
    private var socket: URLSessionWebSocketTask?
    private var worker: Task<Void, Never>?
    private var ready = false
    private var stopping = false
    private var generation = 0
    private var pending: [Data] = []
    private var pendingBytes = 0
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var stoppedContinuation: CheckedContinuation<Void, Never>?
    private let sendQueue = SocketSender()

    var onTranscript: @MainActor (TranscriptionResult) -> Void = { _ in }
    var onReady: @MainActor () -> Void = {}
    var onFailure: @MainActor (TranscriptionFailure) -> Void = { _ in }

    init(backend: BackendClient) { self.backend = backend }

    /// Returns once the provider reports ready.
    func start(sessionId: String, channels: Int) async throws {
        await stop()
        generation += 1
        let current = generation
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            readyContinuation = continuation
            worker = Task { [weak self] in await self?.run(sessionId: sessionId, channels: channels) }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(12))
                guard let self, self.generation == current, self.readyContinuation != nil, !self.ready else { return }
                self.finishStart(BackendError("Timed out connecting to the transcription provider."))
                self.teardown()
            }
        }
    }

    func send(_ frame: Data) {
        guard worker != nil, !frame.isEmpty else { return }
        if ready, let socket {
            sendQueue.send(frame, over: socket)
        } else if pendingBytes + frame.count <= Self.maxPendingBytes {
            pending.append(frame)
            pendingBytes += frame.count
        } else {
            pending = []
            pendingBytes = 0
        }
    }

    /// Asks the provider to flush its final results before closing.
    func stop() async {
        if ready, let socket {
            ready = false
            stopping = true
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                stoppedContinuation = continuation
                sendQueue.send(text: #"{"type":"stop"}"#, over: socket)
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    self?.finishStop()
                }
            }
        }
        finishStart(CancellationError())
        teardown()
    }

    private func teardown() {
        worker?.cancel()
        worker = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        sendQueue.reset()
        ready = false
        stopping = false
        pending = []
        pendingBytes = 0
        finishStop()
    }

    private func finishStart(_ error: Error?) {
        guard let continuation = readyContinuation else { return }
        readyContinuation = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }

    private func finishStop() {
        stoppedContinuation?.resume()
        stoppedContinuation = nil
    }

    private struct Message: Decodable {
        var type: String
        var code: String?
        var message: String?
        var retryable: Bool?
    }

    private func run(sessionId: String, channels: Int) async {
        var attempts = 0
        while !Task.isCancelled {
            var request = URLRequest(url: backend.socketURL("/transcription/stream"))
            for (key, value) in await backend.authHeaders() { request.setValue(value, forHTTPHeaderField: key) }
            request.setValue("granted", forHTTPHeaderField: "x-expo-transcript-consent")
            if Task.isCancelled { return }
            let socket = URLSession.shared.webSocketTask(with: request)
            self.socket = socket
            sendQueue.reset()
            socket.resume()
            var readyAt: ContinuousClock.Instant?
            do {
                let start: [String: Any] = ["type": "start", "sessionId": sessionId, "mimeType": "audio/pcm", "sampleRate": 48_000, "channels": channels]
                let data = try JSONSerialization.data(withJSONObject: start)
                try await socket.send(.string(String(decoding: data, as: UTF8.self)))
                while !Task.isCancelled {
                    let data: Data = switch try await socket.receive() {
                    case .string(let text): Data(text.utf8)
                    case .data(let data): data
                    @unknown default: Data()
                    }
                    if Task.isCancelled { return }
                    guard let message = try? JSONDecoder().decode(Message.self, from: data) else { continue }
                    switch message.type {
                    case "ready":
                        ready = true
                        readyAt = .now
                        pending.forEach { sendQueue.send($0, over: socket) }
                        pending = []
                        pendingBytes = 0
                        onReady()
                        finishStart(nil)
                    case "transcript":
                        if let result = try? JSONDecoder().decode(TranscriptionResult.self, from: data),
                           !result.text.trimmed.isEmpty, result.sessionId == nil || result.sessionId == sessionId {
                            onTranscript(result)
                        }
                    case "stopped":
                        finishStop()
                        return
                    case "error":
                        let text = message.message ?? "The transcription provider reported an error."
                        if readyContinuation != nil {
                            finishStart(BackendError(text, code: message.code))
                            teardown()
                            return
                        }
                        if message.retryable != true {
                            teardown()
                            onFailure(TranscriptionFailure(message: text, permanent: true))
                            return
                        }
                        throw BackendError(text, code: message.code)
                    default:
                        break
                    }
                }
            } catch {
                if Task.isCancelled { return }
                // A close while stopping is expected and must not reconnect.
                if stopping { finishStop(); return }
            }
            ready = false
            socket.cancel(with: .goingAway, reason: nil)
            // A connection that stayed healthy earns a fresh retry budget.
            if let readyAt, ContinuousClock.now - readyAt > .seconds(8) { attempts = 0 }
            if attempts >= Self.maxAttempts {
                finishStart(BackendError("Expo could not restore the transcription connection after five attempts."))
                teardown()
                onFailure(TranscriptionFailure(message: "Expo could not restore the transcription connection after five attempts.", attempt: Self.maxAttempts, exhausted: true))
                return
            }
            onFailure(TranscriptionFailure(message: "Expo lost the transcription connection.", attempt: attempts + 1))
            let delay = min(30_000, 500 * (1 << attempts))
            attempts += 1
            try? await Task.sleep(for: .milliseconds(delay))
        }
    }
}

/// Keeps binary frames in order by sending one at a time.
@MainActor
private final class SocketSender {
    private var chain: Task<Void, Never>?

    func send(_ data: Data, over socket: URLSessionWebSocketTask) { enqueue(.data(data), socket) }
    func send(text: String, over socket: URLSessionWebSocketTask) { enqueue(.string(text), socket) }
    func reset() { chain = nil }

    private func enqueue(_ message: URLSessionWebSocketTask.Message, _ socket: URLSessionWebSocketTask) {
        let previous = chain
        chain = Task {
            await previous?.value
            // A failed send surfaces through the receive loop, which reconnects.
            try? await socket.send(message)
        }
    }
}
