import CryptoKit
import Foundation
import Security

public enum MeetingKeyPurpose: String, Sendable {
    case text
    case audio
}

public protocol MeetingKeyStore: Sendable {
    func createKey(for meetingID: UUID, purpose: MeetingKeyPurpose) async throws -> SymmetricKey
    func key(for meetingID: UUID, purpose: MeetingKeyPurpose) async throws -> SymmetricKey
    func deleteKey(for meetingID: UUID, purpose: MeetingKeyPurpose) async throws
    func deleteKeys(for meetingID: UUID) async throws
    func removeRetiredKeyMaterial(for meetingID: UUID) async throws
    func setGeneration(_ generation: UUID, for meetingID: UUID) async throws
    func generation(for meetingID: UUID) async throws -> UUID
    func deleteGeneration(for meetingID: UUID) async throws
}

public extension MeetingKeyStore {
    func removeRetiredKeyMaterial(for meetingID: UUID) async throws {}
}

public enum MeetingKeyStoreError: Error, Equatable {
    case duplicate
    case missing
    case keychain(OSStatus)
}

public struct KeychainMeetingKeyStore: MeetingKeyStore {
    private let service: String

    public init(service: String = "com.huynguyen.Kineto.meeting-key") {
        self.service = service
    }

    public func createKey(for meetingID: UUID, purpose: MeetingKeyPurpose) async throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        var query = baseQuery(meetingID: meetingID, purpose: purpose)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        query[kSecAttrSynchronizable as String] = false

        let status = SecItemAdd(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return key
        case errSecDuplicateItem:
            throw MeetingKeyStoreError.duplicate
        default:
            throw MeetingKeyStoreError.keychain(status)
        }
    }

    public func key(for meetingID: UUID, purpose: MeetingKeyPurpose) async throws -> SymmetricKey {
        var query = baseQuery(meetingID: meetingID, purpose: purpose)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw MeetingKeyStoreError.missing
            }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            throw MeetingKeyStoreError.missing
        default:
            throw MeetingKeyStoreError.keychain(status)
        }
    }

    public func deleteKey(for meetingID: UUID, purpose: MeetingKeyPurpose) async throws {
        let status = SecItemDelete(baseQuery(meetingID: meetingID, purpose: purpose) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MeetingKeyStoreError.keychain(status)
        }
    }

    public func deleteKeys(for meetingID: UUID) async throws {
        try await deleteKey(for: meetingID, purpose: .text)
        try await deleteKey(for: meetingID, purpose: .audio)
        try await removeRetiredKeyMaterial(for: meetingID)
        try await deleteGeneration(for: meetingID)
    }

    public func setGeneration(_ generation: UUID, for meetingID: UUID) async throws {
        let data = Data(generation.uuidString.utf8)
        let query = metadataQuery(meetingID: meetingID)
        let status = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var insertion = query
            insertion[kSecValueData as String] = data
            insertion[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(insertion as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw MeetingKeyStoreError.keychain(addStatus)
            }
        } else if status != errSecSuccess {
            throw MeetingKeyStoreError.keychain(status)
        }
    }

    public func generation(for meetingID: UUID) async throws -> UUID {
        var query = metadataQuery(meetingID: meetingID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              let generation = UUID(uuidString: value) else {
            if status == errSecItemNotFound { throw MeetingKeyStoreError.missing }
            throw MeetingKeyStoreError.keychain(status)
        }
        return generation
    }

    public func deleteGeneration(for meetingID: UUID) async throws {
        let status = SecItemDelete(metadataQuery(meetingID: meetingID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MeetingKeyStoreError.keychain(status)
        }
    }

    public func removeRetiredKeyMaterial(for meetingID: UUID) async throws {
        let status = SecItemDelete(legacyRetiredKeyQuery(meetingID: meetingID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MeetingKeyStoreError.keychain(status)
        }
    }

    private func baseQuery(meetingID: UUID, purpose: MeetingKeyPurpose) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(meetingID.uuidString).\(purpose.rawValue)",
            kSecAttrSynchronizable as String: false
        ]
    }

    private func legacyRetiredKeyQuery(meetingID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(meetingID.uuidString).attachment",
            kSecAttrSynchronizable as String: false
        ]
    }
    private func metadataQuery(meetingID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(meetingID.uuidString).generation",
            kSecAttrSynchronizable as String: false
        ]
    }

}
