import Foundation

/// What a one-click screen capture asks, and what it leaves in the transcript.
enum ScreenAnswer {
    static let label = "Screen capture"
    static let speaker = "Screen"

    static let request = "Read my screen and answer every question or task you can see on it, in order, without skipping any. Use your own knowledge to answer. Ignore menus, sidebars, adverts and other page furniture. If there is no question, say what is on screen and what I should say or do next."

    /// How the reply is laid out; kept within the server's 300 characters.
    static func format(plainEnglish: Bool) -> String {
        let base = "For each question: its number and a short title in bold on one line, then a clear answer in two to four lines. Add a short fenced code block with its language only where it helps."
        return plainEnglish ? base + " Use simple English." : base
    }

    /// The bold or heading lines of an answer, which name what was on screen.
    static func titles(_ answer: String) -> [String] {
        var inCode = false
        return answer.components(separatedBy: "\n").compactMap { line in
            var text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("```") { inCode.toggle(); return nil }
            guard !inCode else { return nil }
            let heading = text.hasPrefix("#")
            text = String(text.drop { $0 == "#" || $0 == " " })
            let bold = text.hasPrefix("**") && text.hasSuffix("**") && text.count > 4
            // "1. **Title**" is as common as "**1. Title**".
            let numbered = text.firstMatch(of: /^\d+[.)]\s+\*\*(.+)\*\*$/) != nil
            guard heading || bold || numbered else { return nil }
            return text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        }
    }

    /// The transcript line for a capture. The picture itself is never kept.
    static func transcriptNote(source: String, answer: String) -> String {
        let found = titles(answer)
        let head = "Captured \(source) and answered it."
        return String((found.isEmpty ? head : head + " " + found.joined(separator: " · ")).prefix(4_000))
    }
}
