import Foundation

/// Bounded retry with backoff, used to restore audio capture.
enum Recovery {
    static let audioDelays: [Duration] = [.milliseconds(250), .milliseconds(750), .milliseconds(1_500), .seconds(3)]

    enum Outcome: Equatable {
        case restored, abandoned
        case failed(String)
    }

    /// Makes one attempt plus one per delay. `shouldContinue` is checked before
    /// each attempt, so pausing or ending the session stops the loop.
    @MainActor
    static func run(
        delays: [Duration] = audioDelays,
        shouldContinue: () -> Bool,
        isPermanent: (Error) -> Bool = { _ in false },
        onAttempt: (_ attempt: Int, _ total: Int) -> Void = { _, _ in },
        operation: () async throws -> Void
    ) async -> Outcome {
        var message = ""
        for attempt in 1...(delays.count + 1) {
            if attempt > 1 { try? await Task.sleep(for: delays[attempt - 2]) }
            guard shouldContinue() else { return .abandoned }
            onAttempt(attempt, delays.count + 1)
            do {
                try await operation()
                return shouldContinue() ? .restored : .abandoned
            } catch {
                message = error.localizedDescription
                if isPermanent(error) { break }
            }
        }
        return shouldContinue() ? .failed(message) : .abandoned
    }
}
