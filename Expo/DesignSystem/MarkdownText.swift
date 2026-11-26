import SwiftUI

/// Block-level Markdown for answers: headings, lists, code and inline styles.
struct MarkdownText: View {
    var text: String

    private enum Block { case heading(String), bullet(String, String), code(String), paragraph(String) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(Self.parse(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let value): inline(value).font(.system(size: 13.5, weight: .bold))
                case .bullet(let mark, let value):
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(mark).foregroundStyle(Theme.tertiary)
                        inline(value)
                    }
                case .code(let value):
                    ScrollView(.horizontal) {
                        Text(value).font(.system(size: 11.5, design: .monospaced)).padding(10)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.subtle, in: .rect(cornerRadius: 8))
                case .paragraph(let value): inline(value)
                }
            }
        }
        .font(.system(size: 13))
        .textSelection(.enabled)
    }

    private func inline(_ value: String) -> some View {
        let styled = try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        return Text(styled ?? AttributedString(value)).fixedSize(horizontal: false, vertical: true)
    }

    private static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var code: [String]?
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let open = code { blocks.append(.code(open.joined(separator: "\n"))); code = nil } else { code = [] }
                continue
            }
            if code != nil { code?.append(line); continue }
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#") {
                blocks.append(.heading(trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                blocks.append(.bullet("•", String(trimmed.dropFirst(2))))
            } else if let match = trimmed.prefixMatch(of: /(\d+\.)\s/) {
                blocks.append(.bullet(String(match.1), String(trimmed[match.range.upperBound...])))
            } else {
                blocks.append(.paragraph(trimmed))
            }
        }
        // An unterminated fence is still streaming.
        if let code { blocks.append(.code(code.joined(separator: "\n"))) }
        return blocks
    }
}
