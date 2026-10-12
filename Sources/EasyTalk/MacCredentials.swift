import Foundation
import Security
import EasyTalkLearning

protocol MacCredentialVault {
    func read() -> ConnectionSettings?
    func write(_ settings: ConnectionSettings) -> Bool
    func delete() -> Bool
}

/// The Mac has its own key. Never extracts or imports the iPhone's Keychain.
final class MacKeychainVault: MacCredentialVault {
    private let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "easytalk.mac", kSecAttrAccount as String: "connection"]
    func read() -> ConnectionSettings? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let config = try? JSONDecoder().decode(ConnectionSettings.self, from: data), config.url != nil else { return nil }
        return config
    }
    func write(_ settings: ConnectionSettings) -> Bool {
        guard settings.url != nil, let data = try? JSONEncoder().encode(settings) else { return false }
        let values: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        return SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil) == errSecSuccess
    }
    func delete() -> Bool { let status = SecItemDelete(query as CFDictionary); return status == errSecSuccess || status == errSecItemNotFound }
}

final class MemoryCredentialVault: MacCredentialVault {
    var settings: ConnectionSettings?
    func read() -> ConnectionSettings? { settings }
    func write(_ settings: ConnectionSettings) -> Bool { self.settings = settings; return true }
    func delete() -> Bool { settings = nil; return true }
}
