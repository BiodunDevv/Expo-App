import Foundation

/// A loosely typed JSON value for event payloads.
struct EventPayload: Decodable, Sendable {
    var runId: String?
    var contextVersion: Int?
    var status: String?
    var sourceTurnId: String?
    var reason: String?
    var text: String?
    var delta: String?
    var offset: Int?
    var code: String?
    var message: String?
}

struct RealtimeEvent: Sendable {
    var type: String
    var sessionId: String
    var seq: Int
    var contextVersion: Int?
    var payload: EventPayload
}

/// Session event stream with sequence-based replay and exponential reconnect.
@MainActor
final class RealtimeClient {
    private let backend: BackendClient
    private var worker: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?

    init(backend: BackendClient) { self.backend = backend }

    func start(
        sessionId: String,
        onEvent: @escaping @MainActor (RealtimeEvent) -> Void,
        onState: @escaping @MainActor (LinkState) -> Void
    ) {
        stop()
        worker = Task { [weak self] in
            var sequence = 0
            var seen = Set<String>()
            var attempt = 0
            while !Task.isCancelled {
                guard let self else { return }
                var request = URLRequest(url: backend.socketURL("/realtime"))
                for (key, value) in await backend.authHeaders() { request.setValue(value, forHTTPHeaderField: key) }
                if Task.isCancelled { return }
                let socket = URLSession.shared.webSocketTask(with: request)
                socket.maximumMessageSize = 8 * 1024 * 1024
                self.socket = socket
                socket.resume()
                do {
                    var subscribe: [String: Any] = ["type": "subscribe", "sessionId": sessionId]
                    if sequence > 0 { subscribe["sinceSeq"] = sequence }
                    let data = try JSONSerialization.data(withJSONObject: subscribe)
                    try await socket.send(.string(String(decoding: data, as: UTF8.self)))
                    onState(.connected)
                    while !Task.isCancelled {
                        let data: Data = switch try await socket.receive() {
                        case .string(let text): Data(text.utf8)
                        case .data(let data): data
                        @unknown default: Data()
                        }
                        if Task.isCancelled { return }
                        attempt = 0
                        guard let head = try? JSONDecoder().decode(Head.self, from: data),
                              head.sessionId == sessionId, let seq = head.seq else { continue }
                        if head.type == "subscribed" { sequence = max(sequence, seq); continue }
                        if let id = head.eventId, !seen.insert(id).inserted { continue }
                        // Presence is not buffered and may reuse the current sequence.
                        if head.type != "presence.changed" {
                            guard seq > sequence else { continue }
                            sequence = seq
                        }
                        let payload = (try? JSONDecoder().decode(Body.self, from: data))?.data ?? EventPayload()
                        onEvent(RealtimeEvent(type: head.type, sessionId: sessionId, seq: seq, contextVersion: head.contextVersion, payload: payload))
                    }
                } catch {
                    if Task.isCancelled { return }
                }
                socket.cancel(with: .goingAway, reason: nil)
                onState(.reconnecting)
                let delay = min(30_000, 500 * (1 << min(attempt, 6)))
                attempt += 1
                try? await Task.sleep(for: .milliseconds(delay))
            }
        }
    }

    func stop() {
        worker?.cancel()
        worker = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
    }

    private struct Head: Decodable {
        var type: String
        var sessionId: String?
        var seq: Int?
        var eventId: String?
        var contextVersion: Int?
    }

    private struct Body: Decodable { var data: EventPayload? }
}
