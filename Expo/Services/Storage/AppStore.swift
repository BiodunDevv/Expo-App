import CryptoKit
import Foundation
import Observation
import Security

enum StorageError: LocalizedError {
    case keychain(OSStatus)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            "Expo could not access Keychain (\(status)). Unlock the login keychain and allow Expo, then retry. Your encrypted data has not been deleted."
        case .unreadable:
            "Expo could not decrypt your local data. It has been left untouched."
        }
    }
}

struct Keychain: Sendable {
    var service = "core4.Expo"

    func read(_ account: String) throws -> Data? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw StorageError.keychain(status) }
        return data
    }

    func write(_ data: Data, _ account: String) throws {
        let update = [kSecValueData as String: data] as CFDictionary
        var status = SecItemUpdate(base(account) as CFDictionary, update)
        if status == errSecItemNotFound {
            var query = base(account)
            query[kSecValueData as String] = data
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw StorageError.keychain(status) }
    }

    func delete(_ account: String) {
        SecItemDelete(base(account) as CFDictionary)
    }

    private func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

/// Everything on disk: the current state plus an archive per previously used account.
private struct Vault: Codable, Sendable {
    var current = PersistedState()
    var accounts: [String: PersistedState] = [:]
}

/// Writes encrypted snapshots off the main thread, always in order.
private actor VaultWriter {
    let url: URL
    let key: SymmetricKey
    private var latest = 0

    init(url: URL, key: SymmetricKey) { self.url = url; self.key = key }

    func write(_ vault: Vault, revision: Int) throws {
        guard revision > latest else { return }
        latest = revision
        let sealed = try AES.GCM.seal(try JSONEncoder().encode(vault), using: key)
        guard let combined = sealed.combined else { throw StorageError.unreadable }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try combined.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Local-first state, AES-GCM encrypted with a key held in Keychain.
@MainActor
@Observable
final class AppStore {
    private(set) var state = PersistedState()
    var saveError: String?

    @ObservationIgnored private var accounts: [String: PersistedState] = [:]
    @ObservationIgnored private var writer: VaultWriter?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private let keychain: Keychain
    @ObservationIgnored private let fileURL: URL

    init(keychain: Keychain = Keychain(), directory: URL = AppConfig.supportDirectory) {
        self.keychain = keychain
        fileURL = directory.appending(path: "state.enc")
    }

    func load() throws {
        let key: SymmetricKey
        let exists = FileManager.default.fileExists(atPath: fileURL.path)
        if let data = try keychain.read("state-key") {
            key = SymmetricKey(data: data)
        } else {
            // Never silently replace the key while data encrypted with it exists.
            if exists { throw StorageError.unreadable }
            key = SymmetricKey(size: .bits256)
            try keychain.write(key.withUnsafeBytes { Data($0) }, "state-key")
        }
        if exists {
            do {
                let box = try AES.GCM.SealedBox(combined: Data(contentsOf: fileURL))
                let vault = try JSONDecoder().decode(Vault.self, from: AES.GCM.open(box, using: key))
                state = vault.current
                accounts = vault.accounts
            } catch { throw StorageError.unreadable }
        }
        writer = VaultWriter(url: fileURL, key: key)
    }

    var token: String? {
        (try? keychain.read("session-token")).flatMap { $0 }.flatMap { String(data: $0, encoding: .utf8) }
    }

    func setToken(_ token: String?) throws {
        if let token { try keychain.write(Data(token.utf8), "session-token") }
        else { keychain.delete("session-token") }
    }

    func update(_ mutate: (inout PersistedState) -> Void) {
        mutate(&state)
        scheduleSave()
    }

    /// Updates one session in place; does nothing when it no longer exists.
    func updateSession(_ id: String, _ mutate: (inout ExpoSession) -> Void) {
        guard let index = state.sessions.firstIndex(where: { $0.id == id }) else { return }
        mutate(&state.sessions[index])
        scheduleSave()
    }

    func upsert(_ session: ExpoSession) {
        if let index = state.sessions.firstIndex(where: { $0.id == session.id }) {
            state.sessions[index] = session
        } else {
            state.sessions.insert(session, at: 0)
        }
        scheduleSave()
    }

    func session(_ id: String?) -> ExpoSession? {
        guard let id else { return nil }
        return state.sessions.first { $0.id == id }
    }

    func activate(_ account: UserAccount) {
        if let current = state.account?.id, current != account.id {
            accounts[current] = state
            state = accounts[account.id] ?? PersistedState()
        } else if state.account == nil {
            state = accounts[account.id] ?? PersistedState()
        }
        state.account = account
        state.authenticated = true
        scheduleSave()
    }

    func markSignedOut() {
        if let id = state.account?.id {
            var archived = state
            archived.authenticated = false
            accounts[id] = archived
        }
        state = PersistedState()
        scheduleSave()
    }

    func reset() {
        state = PersistedState()
        accounts = [:]
        keychain.delete("session-token")
        scheduleSave()
    }

    private func scheduleSave() {
        guard pendingSave == nil else { return }
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            await self?.flush()
        }
    }

    func flush() async {
        pendingSave = nil
        guard let writer else { return }
        revision += 1
        let vault = Vault(current: state, accounts: accounts)
        do { try await writer.write(vault, revision: revision); saveError = nil }
        catch { saveError = "Expo could not save your local data: \(error.localizedDescription)" }
    }
}
