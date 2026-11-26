import Foundation

/// Runtime configuration. Secrets are never compiled into the app: they are read
/// at launch from the process environment or a local `.env` file.
///
/// Precedence per key (first hit wins):
///   1. Process environment (e.g. an Xcode scheme override)
///   2. `~/Library/Application Support/Expo/.env` (installed configuration)
///   3. The project's `.env` (Debug builds only)
///   4. The local backend URL (URL only, never a key)
struct AppConfig: Sendable, Equatable {
    /// The local backend (see expo-backend/scripts/local-up.sh).
    static let defaultBackendURL = "http://127.0.0.1:3000"
    static let keys = ["EXPO_BACKEND_URL", "EXPO_API_KEY"]

    var backendURL: URL
    var apiKey: String?
    var sources: [String]

    /// A released build may hold no key, in which case only a remote HTTPS backend counts.
    var isBackendConfigured: Bool {
        apiKey != nil || (backendURL.scheme == "https" && !Self.isLoopback(backendURL))
    }

    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Expo", directoryHint: .isDirectory)
    }

    static var candidateFiles: [URL] {
        var files = [supportDirectory.appending(path: ".env")]
        #if DEBUG
        // .../Expo/Expo/Services/System/AppConfig.swift -> .../Expo/.env
        let project = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        files.append(project.appending(path: ".env"))
        #endif
        return files
    }

    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        files: [URL] = candidateFiles
    ) throws -> AppConfig {
        var values: [String: String] = [:]
        var sources: [String] = []
        for key in keys {
            if let value = environment[key] { values[key] = value }
        }
        if !values.isEmpty { sources.append("process environment") }

        for file in files where keys.contains(where: { values[$0] == nil }) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let parsed = parse(text)
            var used = false
            // Only Expo's declared settings are read, never arbitrary flags.
            for key in keys where values[key] == nil {
                if let value = parsed[key] { values[key] = value; used = true }
            }
            if used { sources.append(file.path) }
        }

        let raw = values["EXPO_BACKEND_URL"]?.trimmed.nonEmpty ?? defaultBackendURL
        let url = try validatedBackendURL(raw)
        return AppConfig(
            backendURL: url,
            apiKey: values["EXPO_API_KEY"]?.trimmed.nonEmpty,
            sources: sources
        )
    }

    static func validatedBackendURL(_ raw: String) throws -> URL {
        var text = raw
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), url.host() != nil else {
            throw ConfigError.invalidURL
        }
        guard scheme == "https" || (scheme == "http" && isLoopback(url)) else {
            throw ConfigError.insecureURL
        }
        return url
    }

    static func isLoopback(_ url: URL) -> Bool {
        ["localhost", "127.0.0.1", "::1", "[::1]"].contains(url.host() ?? "")
    }

    static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            var entry = String(line).trimmed
            if entry.isEmpty || entry.hasPrefix("#") { continue }
            if entry.hasPrefix("export ") { entry = String(entry.dropFirst(7)) }
            guard let equals = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[..<equals]).trimmed
            var value = String(entry[entry.index(after: equals)...]).trimmed
            if let quote = value.first, quote == "\"" || quote == "'",
               let end = value.dropFirst().firstIndex(of: quote) {
                value = String(value[value.index(after: value.startIndex)..<end])
            } else if let comment = value.range(of: " #") {
                value = String(value[..<comment.lowerBound]).trimmed
            }
            if !key.isEmpty { result[key] = value }
        }
        return result
    }
}

enum ConfigError: LocalizedError {
    case invalidURL, insecureURL
    var errorDescription: String? {
        switch self {
        case .invalidURL: "EXPO_BACKEND_URL is not a valid URL."
        case .insecureURL: "The backend URL must use HTTPS outside localhost."
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? { isEmpty ? nil : self }
}
