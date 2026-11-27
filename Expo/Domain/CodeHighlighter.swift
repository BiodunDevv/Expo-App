import Foundation

/// A small colouriser for code in answers. It names comments, strings, numbers,
/// keywords and calls well enough to read at a glance; it is not a parser.
enum CodeHighlighter {
    enum Kind: Equatable, Sendable { case plain, keyword, string, number, comment, call }

    struct Span: Equatable, Sendable {
        var text: String
        var kind: Kind
    }

    private static let keywords: Set<String> = [
        "abstract", "and", "as", "async", "await", "begin", "bool", "break", "case", "catch", "chan", "char", "class", "const", "continue",
        "def", "default", "defer", "del", "do", "double", "elif", "else", "end", "enum", "except", "export", "extends", "false", "False",
        "final", "finally", "float", "fn", "for", "from", "func", "function", "go", "guard", "if", "impl", "implements", "import", "in",
        "instanceof", "int", "interface", "is", "lambda", "let", "match", "mut", "new", "nil", "None", "not", "null", "of", "or", "package",
        "pass", "private", "protected", "protocol", "pub", "public", "raise", "return", "self", "static", "string", "struct", "super",
        "switch", "this", "throw", "throws", "true", "True", "try", "type", "typeof", "undefined", "use", "var", "void", "when", "where",
        "while", "with", "yield",
    ]
    private static let sqlKeywords: Set<String> = [
        "select", "from", "where", "join", "left", "right", "inner", "outer", "on", "group", "by", "order", "having", "limit", "insert",
        "into", "values", "update", "set", "delete", "create", "table", "alter", "drop", "and", "or", "not", "null", "as", "distinct",
        "union", "all", "count", "sum", "avg", "max", "min", "case", "when", "then", "else", "end", "desc", "asc",
    ]

    static func spans(_ code: String, language: String) -> [Span] {
        let language = language.lowercased()
        let sql = ["sql", "postgres", "postgresql", "mysql", "sqlite"].contains(language)
        let hashComments = ["python", "py", "ruby", "rb", "bash", "sh", "zsh", "shell", "yaml", "yml", "toml", "dockerfile", "r"].contains(language)
        let markup = ["html", "xml", "text", "txt", "plaintext", "markdown", "md"].contains(language)
        if markup { return [Span(text: code, kind: .plain)] }

        let characters = Array(code)
        var spans: [Span] = []
        var index = 0
        func add(_ text: String, _ kind: Kind) {
            if kind == .plain, spans.last?.kind == .plain { spans[spans.count - 1].text += text }
            else { spans.append(Span(text: text, kind: kind)) }
        }
        func starts(_ prefix: String, at position: Int) -> Bool {
            position + prefix.count <= characters.count && String(characters[position..<position + prefix.count]) == prefix
        }
        /// Takes everything up to and including `end`, or the rest of the code.
        func take(through end: String, from start: Int, skipping opening: Int) -> String {
            var position = start + opening
            while position < characters.count, !starts(end, at: position) { position += 1 }
            position = min(characters.count, position + (end == "\n" ? 0 : end.count))
            defer { index = position }
            return String(characters[start..<position])
        }

        while index < characters.count {
            let character = characters[index]
            if (!hashComments && !sql && starts("//", at: index)) || (hashComments && character == "#") || (sql && starts("--", at: index)) {
                add(take(through: "\n", from: index, skipping: 1), .comment)
            } else if !hashComments && starts("/*", at: index) {
                add(take(through: "*/", from: index, skipping: 2), .comment)
            } else if character == "\"" || character == "'" || character == "`" {
                var position = index + 1
                while position < characters.count, characters[position] != character, characters[position] != "\n" || character == "`" {
                    position += characters[position] == "\\" ? 2 : 1
                }
                if position < characters.count && characters[position] == character {
                    add(String(characters[index...position]), .string)
                    index = position + 1
                } else {
                    // An apostrophe or an unfinished string stays plain.
                    add(String(character), .plain)
                    index += 1
                }
            } else if character.isLetter || character == "_" || character == "$" {
                var position = index
                while position < characters.count, characters[position].isLetter || characters[position].isNumber || characters[position] == "_" || characters[position] == "$" { position += 1 }
                let word = String(characters[index..<position])
                let isKeyword = sql ? sqlKeywords.contains(word.lowercased()) : keywords.contains(word)
                add(word, isKeyword ? .keyword : position < characters.count && characters[position] == "(" ? .call : .plain)
                index = position
            } else if character.isNumber {
                var position = index
                while position < characters.count, characters[position].isNumber || characters[position].isLetter || characters[position] == "." || characters[position] == "_" { position += 1 }
                add(String(characters[index..<position]), .number)
                index = position
            } else {
                add(String(character), .plain)
                index += 1
            }
        }
        return spans
    }
}
