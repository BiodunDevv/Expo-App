import Foundation

/// How much the person spoke and how long it took, from the transcription timings.
struct SpeechTiming: Codable, Hashable, Sendable {
    var seconds = 0.0
    var words = 0

    /// Nil until there is enough speech for the number to mean something.
    var wordsPerMinute: Int? { seconds >= 10 ? Int((Double(words) / seconds * 60).rounded()) : nil }

    var paceNote: String? {
        guard let pace = wordsPerMinute else { return nil }
        if pace < 110 { return "On the slow side" }
        if pace > 170 { return "Fast. Try pausing more" }
        return "A comfortable pace"
    }
}

/// What can be told about a finished practice from its transcript, on this Mac.
struct PracticeReview: Equatable, Sendable {
    struct Exchange: Identifiable, Equatable, Sendable {
        let id: String
        let question: String
        let suggested: String
        let reply: String
    }

    struct Filler: Equatable, Sendable {
        let phrase: String
        let count: Int
    }

    var wordCount = 0
    var fillers: [Filler] = []
    var exchanges: [Exchange] = []

    var fillerCount: Int { fillers.reduce(0) { $0 + $1.count } }

    private static let fillerPhrases = ["um", "uh", "erm", "you know", "i mean", "basically", "actually", "literally", "sort of", "kind of"]

    static let coachingRequest = "Review my practice in this session, using only the transcript lines marked You as what I said. Give two things I did well, three things to improve (each with what I said and a better way to say it), and one thing to practise next. If I said too little to judge, say so plainly."
    static let coachingFormat = "Write coaching addressed to me as \"you\", not a reply for me to say. Use short bold headings with bullet points under each."

    static func words(_ text: String) -> [String] {
        text.lowercased().split { !($0.isLetter || $0.isNumber || $0 == "'" || $0 == "’") }.map(String.init)
    }

    init(session: ExpoSession) {
        let mine = session.transcript.filter { $0.speaker == "You" }
        let spoken = mine.map { " " + Self.words($0.text).joined(separator: " ") + " " }
        wordCount = mine.reduce(0) { $0 + Self.words($1.text).count }
        fillers = Self.fillerPhrases.compactMap { phrase in
            let count = spoken.reduce(0) { total, line in
                // Neighbouring matches share a space, so each is counted word by word.
                let words = line.split(separator: " "), parts = phrase.split(separator: " ")
                guard words.count >= parts.count else { return total }
                return total + (0...(words.count - parts.count)).filter { Array(words[$0..<$0 + parts.count]) == parts }.count
            }
            return count > 0 ? Filler(phrase: phrase, count: count) : nil
        }
        .sorted { $0.count > $1.count }
        exchanges = Self.exchanges(session, mine: mine)
    }

    /// Pairs each suggested answer with what the person said before the next one.
    private static func exchanges(_ session: ExpoSession, mine: [TranscriptSegment]) -> [Exchange] {
        guard let start = ISO.date(session.startedAt) else { return [] }
        typealias Answer = (id: String, at: Double, question: String, text: String)
        var answers: [Answer] = session.assistantMessages.compactMap { message in
            message.createdAt.flatMap(ISO.date).map { (message.id, $0.timeIntervalSince(start), message.question, message.summary) }
        }
        answers += session.liveSuggestions.compactMap { suggestion in
            guard suggestion.status == "completed", suggestion.trigger == "manual", let created = ISO.date(suggestion.createdAt) else { return nil }
            return (suggestion.id, created.timeIntervalSince(start), "What should I say?", suggestion.text)
        }
        answers.sort { $0.at < $1.at }
        func seconds(_ at: String) -> Double { at.split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) } }
        return answers.enumerated().compactMap { index, answer in
            let end = index + 1 < answers.count ? answers[index + 1].at.rounded(.down) : .infinity
            let question = words(answer.question).joined(separator: " ")
            let reply = mine.filter { line in
                let at = seconds(line.at)
                // The question itself, asked aloud, is not the reply to it.
                return at >= answer.at.rounded(.down) && at < end
                    && !question.contains(words(line.text).joined(separator: " "))
            }
            .map(\.text).joined(separator: " ")
            return reply.isEmpty ? nil : Exchange(id: answer.id, question: answer.question, suggested: answer.text, reply: reply)
        }
    }
}
