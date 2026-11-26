import Foundation

// A practice session is a real Assist session used for rehearsal: the same
// listening, answers, transcript and notes. It is recognised by its title, which
// the server stores, so it stays a practice session on every device.

enum PracticeKind: String, CaseIterable, Identifiable, Sendable {
    case interview, sales, presentation, conversation
    var id: Self { self }

    var title: String {
        switch self {
        case .interview: "Interview"
        case .sales: "Sales call"
        case .presentation: "Presentation Q&A"
        case .conversation: "Hard conversation"
        }
    }

    var topicPrompt: String {
        switch self {
        case .interview: "The role and company, or paste the job description"
        case .sales: "What you sell, who you are meeting, and your goal"
        case .presentation: "What you are presenting and who will be listening"
        case .conversation: "Who it is with, what it is about, and what you want"
        }
    }

    var icon: String {
        switch self {
        case .interview: "resume"
        case .sales: "plan"
        case .presentation: "star"
        case .conversation: "chat"
        }
    }

    fileprivate var scene: String {
        switch self {
        case .interview: "a job interview"
        case .sales: "a sales call with a prospective customer"
        case .presentation: "the questions after a presentation"
        case .conversation: "a difficult workplace conversation"
        }
    }
}

enum PracticeSession {
    private static let prefix = "Practice · "

    static func isPractice(_ title: String) -> Bool { title.hasPrefix(prefix) }

    static func title(_ kind: PracticeKind, topic: String) -> String {
        let line = topic.split(whereSeparator: \.isNewline).first.map { String($0).trimmed } ?? ""
        let name = line.isEmpty ? kind.title : "\(kind.title): \(line)"
        return String((prefix + name).prefix(120))
    }

    /// The title without the marker, for lists that already say it is practice.
    static func name(_ title: String) -> String { isPractice(title) ? String(title.dropFirst(prefix.count)) : title }

    /// What the assistant is told about the rehearsal.
    static func brief(_ kind: PracticeKind, topic: String) -> String {
        var text = "This is a practice session: I am rehearsing \(kind.scene), not in a real one. When you receive a question or remark, answer it as a strong reply I can practise saying aloud, in the first person, concise and natural. Use [brackets] for any detail about me that you do not know."
        let topic = topic.trimmed
        if !topic.isEmpty { text += "\n\nContext: \(topic)" }
        return String(text.prefix(MeetingBrief.maxCharacters))
    }
}
