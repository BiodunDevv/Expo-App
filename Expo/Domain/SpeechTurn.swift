import Foundation

/// Gathers what is heard into one message and sends it at the next pause.
/// Nothing is judged or filtered out beyond bare hesitation sounds.
struct SpeechTurn: Equatable, Sendable {
    static let limit = 1_000
    /// A pause this long ends the turn.
    static let settle: Duration = .milliseconds(700)

    private(set) var text = ""
    private var lastSent = ""
    private var lastSentAt = Date.distantPast

    private static var hesitation: Regex<Substring> { /(?:u+m+|u+h+|e+r+m*|h+m+|m+h*m*|a+h+|e+h+)/ }

    /// False for "um", "uh" and the like on their own.
    static func isSpeech(_ fragment: String) -> Bool {
        fragment.lowercased().split { !$0.isLetter && !$0.isNumber }.contains { $0.wholeMatch(of: hesitation) == nil }
    }

    /// Adds a finished line. Newest words win when a turn grows past the limit.
    mutating func add(_ fragment: String) -> Bool {
        let fragment = fragment.trimmed
        guard Self.isSpeech(fragment) else { return false }
        text = String([text, fragment].filter { !$0.isEmpty }.joined(separator: " ").suffix(Self.limit))
        return true
    }

    /// Takes the turn to send. The same words repeated within a few seconds (an
    /// echo) are sent once.
    mutating func take(at now: Date) -> String? {
        let message = text
        text = ""
        func plain(_ value: String) -> String { value.lowercased().filter { $0.isLetter || $0.isNumber } }
        guard !message.isEmpty, plain(message) != plain(lastSent) || now.timeIntervalSince(lastSentAt) > 8 else { return nil }
        lastSent = message
        lastSentAt = now
        return message
    }

    mutating func clear() { text = "" }
}
