import SwiftUI

/// Block-level Markdown for answers: headings, lists, code and inline styles.
struct MarkdownText: View {
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let value): inline(value).font(.system(size: 14, weight: .bold)).padding(.top, 3)
                case .bullet(let mark, let value):
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(mark).foregroundStyle(Theme.secondary).monospacedDigit()
                        inline(value)
                    }
                case .code(let language, let value): CodeBlock(language: language, code: value).padding(.vertical, 2)
                case .paragraph(let value): inline(value)
                }
            }
        }
        .font(.system(size: 13))
        .lineSpacing(2)
        .textSelection(.enabled)
    }

    private func inline(_ value: String) -> some View {
        var styled = (try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value)
        // Inline code gets a tint so names stand out from the sentence.
        for run in styled.runs where run.inlinePresentationIntent?.contains(.code) == true {
            styled[run.range].backgroundColor = Theme.text.opacity(0.12)
        }
        return Text(styled).fixedSize(horizontal: false, vertical: true).textHalo()
    }
}
