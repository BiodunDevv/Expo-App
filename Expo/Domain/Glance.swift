import Foundation

/// An answer reduced to what can be read while someone is talking: one headline
/// and up to three points. Nothing is rewritten; text is only selected.
struct Glance: Equatable {
    static let maxPoints = 3

    var headline: String
    var points: [String]
    /// The answer says more than is shown here.
    var truncated: Bool

    init(_ markdown: String) {
        var prose: [String] = []
        var bullets: [String] = []
        var proseBeforeBullets = 0
        var inCode = false
        var hasCode = false

        for raw in markdown.components(separatedBy: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { inCode.toggle(); hasCode = true; continue }
            if inCode || line.isEmpty { continue }
            let isHeading = line.hasPrefix("#")
            line = String(line.drop { $0 == "#" || $0 == ">" }).trimmingCharacters(in: .whitespaces)
            var isBullet = false
            if !isHeading, let marker = line.prefixMatch(of: /(?:[-*•]|\d+[.)])\s+/) {
                line = String(line[marker.range.upperBound...])
                isBullet = true
            }
            line = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "").replacingOccurrences(of: "`", with: "")
            if line.isEmpty { continue }
            if isBullet { bullets.append(line) }
            else {
                prose.append(contentsOf: Self.sentences(line))
                if bullets.isEmpty { proseBeforeBullets = prose.count }
            }
        }

        let first: String
        if proseBeforeBullets > 0 { first = prose.removeFirst() }
        else if !bullets.isEmpty { first = bullets.removeFirst() }
        else if !prose.isEmpty { first = prose.removeFirst() }
        else { first = "" }
        headline = first.hasSuffix(":") ? String(first.dropLast()) : first

        // Lists carry the substance; plain sentences stand in when there is none.
        let candidates = bullets.isEmpty ? prose : bullets
        points = Array(candidates.prefix(Self.maxPoints))
        let hidden = bullets.isEmpty ? prose.count - points.count : bullets.count - points.count + prose.count
        truncated = hasCode || hidden > 0
    }

    private static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { value, _, _, _ in
            if let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty { result.append(value) }
        }
        return result.isEmpty ? [text] : result
    }
}

/// Follow-ups offered on the answer card.
enum Refinement: String, CaseIterable, Identifiable {
    case shorter = "Shorter", example = "Example", simpler = "Simpler"
    var id: Self { self }

    /// The question limit accepted for one ask.
    static let limit = 1_000

    private var instruction: String {
        switch self {
        case .shorter: "Make this answer shorter: one headline and at most three brief points."
        case .example: "Give one concrete example I could say for this answer."
        case .simpler: "Explain this answer in simpler, everyday words."
        }
    }

    /// The previous answer travels with the request so it cannot be mistaken.
    func prompt(for answer: String) -> String {
        let lead = instruction + "\n\nAnswer:\n"
        return lead + String(answer.prefix(Self.limit - lead.count))
    }
}
