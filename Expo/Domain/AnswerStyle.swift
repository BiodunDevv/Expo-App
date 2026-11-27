import Foundation

/// How the person wants answers written during a session.
enum AnswerStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard, bullets, short, script
    var id: Self { self }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .bullets: "Bullets"
        case .short: "Short"
        case .script: "Full script"
        }
    }

    var detail: String {
        switch self {
        case .standard: "A concise answer, as Expo writes it by default."
        case .bullets: "A few key points you can glance at."
        case .short: "One or two sentences."
        case .script: "The whole reply, word for word, to read aloud."
        }
    }

    private var rule: String? {
        switch self {
        case .standard: nil
        case .bullets: "Answer as three to five short bullet points of a few words each."
        case .short: "Answer in no more than two short sentences."
        case .script: "Write the whole reply word for word, ready to read aloud, in short natural paragraphs."
        }
    }

    /// What the assistant is told, or nil when the default needs no instruction.
    func instruction(plainEnglish: Bool) -> String? {
        let plain = plainEnglish ? "Use simple, everyday English and short sentences." : nil
        return [rule, plain].compactMap { $0 }.joined(separator: " ").nonEmpty
    }
}
