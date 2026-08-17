import Foundation
import Security

public enum ChatProviderAccountStoreError: Error, Equatable, Sendable {
    case emptyKey
    case appleHasNoSecret
    case keychain(OSStatus)
}

public protocol ChatProviderAccountStoring: Sendable {
    func saveAPIKey(_ key: String, for provider: ChatProviderID) async throws
    func apiKey(for provider: ChatProviderID) async throws -> String?
    func deleteAPIKey(for provider: ChatProviderID) async throws
    func isConnected(_ provider: ChatProviderID) async -> Bool
    func account(for provider: ChatProviderID) async -> ChatProviderAccount
    func accounts() async -> [ChatProviderAccount]
}

/// Device-only Keychain store for BYOK provider secrets.
/// Never writes into meeting packages. Never logs the secret.
public actor ChatProviderAccountStore: ChatProviderAccountStoring {
    private let service: String

    public init(service: String = "com.huynguyen.Kineto.chat-provider") {
        self.service = service
    }

    public func saveAPIKey(_ key: String, for provider: ChatProviderID) async throws {
        guard provider.sendsMeetingExcerptsOffDevice else {
            throw ChatProviderAccountStoreError.appleHasNoSecret
        }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ChatProviderAccountStoreError.emptyKey
        }
        let data = Data(trimmed.utf8)
        var query = baseQuery(for: provider)
        let status = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            query[kSecAttrSynchronizable as String] = false
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw ChatProviderAccountStoreError.keychain(addStatus)
            }
        } else if status != errSecSuccess {
            throw ChatProviderAccountStoreError.keychain(status)
        }
    }

    public func apiKey(for provider: ChatProviderID) async throws -> String? {
        guard provider.sendsMeetingExcerptsOffDevice else { return nil }
        var query = baseQuery(for: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8),
                  !value.isEmpty else {
                return nil
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw ChatProviderAccountStoreError.keychain(status)
        }
    }

    public func deleteAPIKey(for provider: ChatProviderID) async throws {
        let status = SecItemDelete(baseQuery(for: provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ChatProviderAccountStoreError.keychain(status)
        }
    }

    public func isConnected(_ provider: ChatProviderID) async -> Bool {
        if provider == .appleOnDevice { return true }
        return (try? await apiKey(for: provider))?.isEmpty == false
    }

    public func account(for provider: ChatProviderID) async -> ChatProviderAccount {
        if provider == .appleOnDevice {
            return ChatProviderAccount(
                provider: provider,
                isConnected: true,
                displayHint: "Apple Intelligence when this Mac supports it"
            )
        }
        guard let key = try? await apiKey(for: provider), !key.isEmpty else {
            return ChatProviderAccount(
                provider: provider,
                isConnected: false,
                displayHint: "Not connected"
            )
        }
        return ChatProviderAccount(
            provider: provider,
            isConnected: true,
            displayHint: Self.hint(for: key)
        )
    }

    public func accounts() async -> [ChatProviderAccount] {
        var result: [ChatProviderAccount] = []
        for provider in ChatProviderID.allCases {
            result.append(await account(for: provider))
        }
        return result
    }

    public static func hint(for key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return "Connected" }
        return "Connected · …\(trimmed.suffix(4))"
    }

    private func baseQuery(for provider: ChatProviderID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.keychainAccount,
            kSecAttrSynchronizable as String: false
        ]
    }
}

/// In-memory store for Core tests. Never used by the app.
public actor InMemoryChatProviderAccountStore: ChatProviderAccountStoring {
    private var keys: [ChatProviderID: String] = [:]

    public init() {}

    public func saveAPIKey(_ key: String, for provider: ChatProviderID) async throws {
        guard provider.sendsMeetingExcerptsOffDevice else {
            throw ChatProviderAccountStoreError.appleHasNoSecret
        }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ChatProviderAccountStoreError.emptyKey }
        keys[provider] = trimmed
    }

    public func apiKey(for provider: ChatProviderID) async throws -> String? {
        keys[provider]
    }

    public func deleteAPIKey(for provider: ChatProviderID) async throws {
        keys[provider] = nil
    }

    public func isConnected(_ provider: ChatProviderID) async -> Bool {
        if provider == .appleOnDevice { return true }
        return keys[provider]?.isEmpty == false
    }

    public func account(for provider: ChatProviderID) async -> ChatProviderAccount {
        if provider == .appleOnDevice {
            return ChatProviderAccount(provider: provider, isConnected: true, displayHint: "On this Mac")
        }
        if let key = keys[provider] {
            return ChatProviderAccount(
                provider: provider,
                isConnected: true,
                displayHint: ChatProviderAccountStore.hint(for: key)
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
