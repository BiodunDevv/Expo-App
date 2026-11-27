import SwiftUI

/// Code in an answer: its language, a copy button, line numbers and colour. It
/// stays dark in every appearance so it reads the same over anything.
struct CodeBlock: View {
    var language: String
    var code: String
    @State private var copied = false
    @Environment(\.onGlass) private var onGlass

    private static let names = [
        "js": "JavaScript", "javascript": "JavaScript", "jsx": "JSX", "ts": "TypeScript", "typescript": "TypeScript", "tsx": "TSX",
        "py": "Python", "python": "Python", "swift": "Swift", "sh": "Shell", "bash": "Shell", "zsh": "Shell", "shell": "Shell",
        "json": "JSON", "html": "HTML", "css": "CSS", "sql": "SQL", "java": "Java", "kotlin": "Kotlin", "go": "Go", "rust": "Rust",
        "rb": "Ruby", "ruby": "Ruby", "c": "C", "cpp": "C++", "c++": "C++", "csharp": "C#", "cs": "C#", "php": "PHP", "yaml": "YAML", "yml": "YAML",
    ]

    var body: some View {
        let lines = code.components(separatedBy: "\n")
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 10, weight: .bold))
                Text(Self.names[language.lowercased()] ?? (language.isEmpty ? "Code" : language)).font(.system(size: 11, weight: .semibold))
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10.5, weight: .semibold))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copied ? "Code copied" : "Copy code")
            }
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 12).frame(height: 30)
            .background(.white.opacity(0.07))
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    if lines.count > 1 {
                        Text((1...lines.count).map(String.init).joined(separator: "\n"))
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.white.opacity(0.32))
                            .textSelection(.disabled)
                            .accessibilityHidden(true)
                    }
                    Text(Self.coloured(code, language: language))
                        .textSelection(.enabled)
                        .textHalo()
                }
                .font(.system(size: 12, design: .monospaced))
                .lineSpacing(3)
                .fixedSize()
                .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // On see-through glass the block lets a little through, like the window.
        .background(Color(.sRGB, red: 0.086, green: 0.094, blue: 0.114).opacity(onGlass ? 0.62 : 1), in: .rect(cornerRadius: 16))
        .clipShape(.rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)) }
    }

    private static func coloured(_ code: String, language: String) -> AttributedString {
        CodeHighlighter.spans(code, language: language).reduce(into: AttributedString()) { result, span in
            var part = AttributedString(span.text)
            part.foregroundColor = switch span.kind {
            case .plain: Color(light: 0xE6E8EE, dark: 0xE6E8EE)
            case .keyword: Color(light: 0xD7A0F5, dark: 0xD7A0F5)
            case .string: Color(light: 0x9BDB8F, dark: 0x9BDB8F)
            case .number: Color(light: 0xF5B97A, dark: 0xF5B97A)
            case .comment: Color(light: 0x8C93A3, dark: 0x8C93A3)
            case .call: Color(light: 0x86C5FF, dark: 0x86C5FF)
            }
            result += part
        }
    }
}
