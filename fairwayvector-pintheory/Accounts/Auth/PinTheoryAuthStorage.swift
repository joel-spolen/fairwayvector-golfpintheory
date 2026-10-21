import Auth
import Foundation
import Security

/// Separate service per canonical project host; no shared access group, iCloud
/// synchronization or device migration. Only foreground, unlocked access is allowed.
nonisolated final class PinTheoryKeychainAuthStorage: AuthLocalStorage {
    private let service: String

    init(configuration: PinTheoryAuthConfiguration) {
        service = "com.fairwayvector.pintheory.auth.\(configuration.projectURL.host!)"
    }

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: key,
         kSecAttrSynchronizable as String: false]
    }

    func store(key: String, value: Data) throws {
        let attributes: [String: Any] = [kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let result = SecItemUpdate(query(key) as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            var item = query(key)
            item.merge(attributes) { _, new in new }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw PinTheoryAuthError.secureStorageUnavailable
            }
        } else if result != errSecSuccess {
            throw PinTheoryAuthError.secureStorageUnavailable
        }
    }

    func retrieve(key: String) throws -> Data? {
        var item = query(key)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw PinTheoryAuthError.secureStorageUnavailable
        }
        return data
    }

    func remove(key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PinTheoryAuthError.secureStorageUnavailable
        }
    }
}

/// One lease per SDK client. The lock covers the underlying operation as well
/// as revocation: an old SDK response cannot write/delete a newer client's data.
/// Only the two SDK 2.55.4 keys are admitted; legacy global migrations are ignored.
nonisolated final class PinTheoryAuthStorageLease: AuthLocalStorage, @unchecked Sendable {
    static let sessionKey = "session-v1"
    static let verifierKey = "session-v1-code-verifier"
    static let confirmationKey = "server-confirmed-user-v1"
    // Service-owned only; never exposed to the SDK lease. No identity/password.
    static let recoveryKey = "password-recovery-required-v1"
    static let pendingRecoveryKey = "password-recovery-request-v1"
    private let storage: any AuthLocalStorage
    private let lock = NSLock()
    private var active = true

    init(storage: any AuthLocalStorage) { self.storage = storage }

    func revoke() {
        lock.lock()
        defer { lock.unlock() }
        active = false
    }

    private func allowed(_ key: String) -> Bool {
        key == Self.sessionKey || key == Self.verifierKey
    }

    func store(key: String, value: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        guard active, allowed(key) else { throw PinTheoryAuthError.cancelled }
        try storage.store(key: key, value: value)
    }

    func retrieve(key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard active, allowed(key) else { return nil }
        return try storage.retrieve(key: key)
    }

    func remove(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard active, allowed(key) else { return }
        try storage.remove(key: key)
    }
}