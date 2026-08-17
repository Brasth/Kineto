import Foundation
import Security

public enum ChatProviderAccountStoreError: Error, Equatable, Sendable {
    case emptyKey
    case appleHasNoSecret
    case keychain(OSStatus)
}

public protocol ChatProviderAccountStoring: Sendable {
    func saveAPIKey(_ key: String, for provider: ChatProviderID) async throws
    func saveSecret(_ secret: ChatProviderSecret, for provider: ChatProviderID) async throws
    func secret(for provider: ChatProviderID) async throws -> ChatProviderSecret?
    func apiKey(for provider: ChatProviderID) async throws -> String?
    func deleteAPIKey(for provider: ChatProviderID) async throws
    func saveOAuthClient(_ config: ChatOAuthClientConfig, for provider: ChatProviderID) async throws
    func oauthClient(for provider: ChatProviderID) async throws -> ChatOAuthClientConfig?
    func isConnected(_ provider: ChatProviderID) async -> Bool
    func account(for provider: ChatProviderID) async -> ChatProviderAccount
    func accounts() async -> [ChatProviderAccount]
}

/// Device-only Keychain store for BYOK and official OAuth secrets.
/// Never writes into meeting packages. Never logs the secret.
public actor ChatProviderAccountStore: ChatProviderAccountStoring {
    private let service: String

    public init(service: String = "com.huynguyen.Kineto.chat-provider") {
        self.service = service
    }

    public func saveAPIKey(_ key: String, for provider: ChatProviderID) async throws {
        try await saveSecret(.apiKey(key), for: provider)
    }

    public func saveSecret(_ secret: ChatProviderSecret, for provider: ChatProviderID) async throws {
        guard provider.sendsMeetingExcerptsOffDevice else {
            throw ChatProviderAccountStoreError.appleHasNoSecret
        }
        guard secret.requestToken != nil else {
            throw ChatProviderAccountStoreError.emptyKey
        }
        try writeItem(try JSONEncoder().encode(secret), account: provider.keychainAccount)
    }

    public func secret(for provider: ChatProviderID) async throws -> ChatProviderSecret? {
        guard provider.sendsMeetingExcerptsOffDevice else { return nil }
        guard let data = try readItem(account: provider.keychainAccount) else { return nil }
        if let decoded = try? JSONDecoder().decode(ChatProviderSecret.self, from: data),
           decoded.requestToken != nil {
            return decoded
        }
        guard let legacy = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !legacy.isEmpty else {
            return nil
        }
        return .apiKey(legacy)
    }

    public func apiKey(for provider: ChatProviderID) async throws -> String? {
        try await secret(for: provider)?.requestToken
    }

    public func deleteAPIKey(for provider: ChatProviderID) async throws {
        try deleteItem(account: provider.keychainAccount)
    }

    public func saveOAuthClient(_ config: ChatOAuthClientConfig, for provider: ChatProviderID) async throws {
        guard provider.sendsMeetingExcerptsOffDevice, !config.clientID.isEmpty else {
            throw ChatProviderAccountStoreError.emptyKey
        }
        try writeItem(try JSONEncoder().encode(config), account: provider.oauthClientAccount)
    }

    public func oauthClient(for provider: ChatProviderID) async throws -> ChatOAuthClientConfig? {
        guard let data = try readItem(account: provider.oauthClientAccount) else { return nil }
        return try JSONDecoder().decode(ChatOAuthClientConfig.self, from: data)
    }

    public func isConnected(_ provider: ChatProviderID) async -> Bool {
        if provider == .appleOnDevice { return true }
        return (try? await secret(for: provider))?.requestToken != nil
    }

    public func account(for provider: ChatProviderID) async -> ChatProviderAccount {
        if provider == .appleOnDevice {
            return ChatProviderAccount(
                provider: provider,
                isConnected: true,
                displayHint: "Apple Intelligence when this Mac supports it"
            )
        }
        guard let secret = try? await secret(for: provider), secret.requestToken != nil else {
            return ChatProviderAccount(
                provider: provider,
                isConnected: false,
                displayHint: "Not connected"
            )
        }
        return ChatProviderAccount(
            provider: provider,
            isConnected: true,
            displayHint: Self.hint(for: secret)
        )
    }

    public func accounts() async -> [ChatProviderAccount] {
        var result: [ChatProviderAccount] = []
        for provider in ChatProviderID.allCases {
            result.append(await account(for: provider))
        }
        return result
    }

    public static func hint(for secret: ChatProviderSecret) -> String {
        switch secret.kind {
        case .oauth:
            return "Signed in with Google"
        case .apiKey:
            return hint(for: secret.apiKey ?? "")
        }
    }

    public static func hint(for key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return "Connected" }
        return "Connected · …\(trimmed.suffix(4))"
    }

    private func writeItem(_ data: Data, account: String) throws {
        var query = baseQuery(account: account)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            query[kSecAttrSynchronizable as String] = false
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw ChatProviderAccountStoreError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw ChatProviderAccountStoreError.keychain(status)
        }
    }

    private func readItem(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw ChatProviderAccountStoreError.keychain(status)
        }
    }

    private func deleteItem(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ChatProviderAccountStoreError.keychain(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }
}

/// In-memory store for Core tests. Never used by the app.
public actor InMemoryChatProviderAccountStore: ChatProviderAccountStoring {
    private var secrets: [ChatProviderID: ChatProviderSecret] = [:]
    private var clients: [ChatProviderID: ChatOAuthClientConfig] = [:]

    public init() {}

    public func saveAPIKey(_ key: String, for provider: ChatProviderID) async throws {
        try await saveSecret(.apiKey(key), for: provider)
    }

    public func saveSecret(_ secret: ChatProviderSecret, for provider: ChatProviderID) async throws {
        guard provider.sendsMeetingExcerptsOffDevice else {
            throw ChatProviderAccountStoreError.appleHasNoSecret
        }
        guard secret.requestToken != nil else { throw ChatProviderAccountStoreError.emptyKey }
        secrets[provider] = secret
    }

    public func secret(for provider: ChatProviderID) async throws -> ChatProviderSecret? {
        secrets[provider]
    }

    public func apiKey(for provider: ChatProviderID) async throws -> String? {
        secrets[provider]?.requestToken
    }

    public func deleteAPIKey(for provider: ChatProviderID) async throws {
        secrets[provider] = nil
    }

    public func saveOAuthClient(_ config: ChatOAuthClientConfig, for provider: ChatProviderID) async throws {
        guard !config.clientID.isEmpty else { throw ChatProviderAccountStoreError.emptyKey }
        clients[provider] = config
    }

    public func oauthClient(for provider: ChatProviderID) async throws -> ChatOAuthClientConfig? {
        clients[provider]
    }

    public func isConnected(_ provider: ChatProviderID) async -> Bool {
        if provider == .appleOnDevice { return true }
        return secrets[provider]?.requestToken != nil
    }

    public func account(for provider: ChatProviderID) async -> ChatProviderAccount {
        if provider == .appleOnDevice {
            return ChatProviderAccount(provider: provider, isConnected: true, displayHint: "On this Mac")
        }
        if let secret = secrets[provider], secret.requestToken != nil {
            return ChatProviderAccount(
                provider: provider,
                isConnected: true,
                displayHint: ChatProviderAccountStore.hint(for: secret)
            )
        }
        return ChatProviderAccount(provider: provider, isConnected: false, displayHint: "Not connected")
    }

    public func accounts() async -> [ChatProviderAccount] {
        var result: [ChatProviderAccount] = []
        for provider in ChatProviderID.allCases {
            result.append(await account(for: provider))
        }
        return result
    }
}
