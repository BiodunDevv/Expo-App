import Foundation

/// The block structure of an answer: headings, lists, code and paragraphs.
enum MarkdownBlock: Equatable, Sendable {
    case heading(String)
    case bullet(mark: String, text: String)
    case code(language: String, text: String)
    case paragraph(String)

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var code: (language: String, indent: Int, lines: [String])?
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let open = code {
                    blocks.append(.code(language: open.language, text: open.lines.joined(separator: "\n")))
                    code = nil
                } else {
                    let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    code = (String(language.prefix { !$0.isWhitespace }), line.prefix { $0 == " " }.count, [])
                }
                continue
            }
            if let open = code {
                // A fence inside a list is indented; that indent is not code.
                code?.lines.append(String(line.dropFirst(min(open.indent, line.prefix { $0 == " " }.count))))
                continue
            }
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#") {
                blocks.append(.heading(trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                blocks.append(.bullet(mark: "•", text: String(trimmed.dropFirst(2))))
            } else if let match = trimmed.prefixMatch(of: /(\d+\.)\s/) {
                blocks.append(.bullet(mark: String(match.1), text: String(trimmed[match.range.upperBound...])))
            } else {
                blocks.append(.paragraph(trimmed))
            }
        }
        // An unterminated fence is still streaming.
        if let code { blocks.append(.code(language: code.language, text: code.lines.joined(separator: "\n"))) }
        return blocks
    }
}
