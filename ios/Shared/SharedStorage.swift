import Foundation
import Security

/// Data shared by the app and the keyboard: one App Group for UserDefaults and Keychain.
/// The group comes from Info.plist (`EasyTalkAppGroup` = `$(APP_GROUP_IDENTIFIER)`), so a
/// different bundle prefix in CI changes it in one build setting.
public enum SharedStorage {
    public static var appGroup: String? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "EasyTalkAppGroup") as? String,
              !group.isEmpty, !group.contains("$("),
              FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil else { return nil }
        return group
    }

    /// The keyboard may use the shared container only with Full Access; without it, its own defaults.
    public static func defaults(shared: Bool = true) -> UserDefaults {
        guard shared, let group = appGroup, let defaults = UserDefaults(suiteName: group) else { return .standard }
        return defaults
    }

    static let legacyPrefixes = ["learning.", "practice.", "rewards.", "keyboard.", "history."]

    /// Copies the old per-process data into the shared container once per process.
    /// Never overwrites a key that already exists there; the old copy stays untouched.
    public static func migrateLegacyDefaults(from legacy: UserDefaults = .standard, to shared: UserDefaults, process: String) {
        guard shared !== legacy else { return }
        let flag = "migration.v1." + process
        guard !shared.bool(forKey: flag) else { return }
        for (key, value) in legacy.dictionaryRepresentation()
        where legacyPrefixes.contains(where: { key.hasPrefix($0) }) && shared.object(forKey: key) == nil {
            shared.set(value, forKey: key)
        }
        shared.set(true, forKey: flag)
    }
}

/// The AI connection in the shared Keychain group: the app writes it, the keyboard reads it.
/// Replaces the former copy through the general pasteboard.
public enum ConnectionStore {
    static let service = "easytalk.connection", account = "connection"
    /// Before App Groups the app and the keyboard each kept their own copy.
    static let legacyServices = ["easytalk.app", "easytalk.keyboard"]
    #if targetEnvironment(simulator)
    public static var isolatedPreview = false
    public static var previewConnection: ConnectionSettings?
    #endif

    public static func read() -> ConnectionSettings? {
        #if targetEnvironment(simulator)
        if isolatedPreview { return previewConnection }
        #endif
        if let data = readData(service: service, group: SharedStorage.appGroup) ?? readData(service: service, group: nil) {
            return decode(data)
        }
        for legacy in legacyServices {
            guard let data = readData(service: legacy, group: nil), let config = decode(data) else { continue }
            if write(config) { _ = delete(service: legacy, group: nil) }
            return config
        }
        return nil
    }

    @discardableResult public static func write(_ config: ConnectionSettings) -> Bool {
        #if targetEnvironment(simulator)
        if isolatedPreview { previewConnection = config; return config.url != nil }
        #endif
        guard config.url != nil, let data = try? JSONEncoder().encode(config) else { return false }
        let group = SharedStorage.appGroup
        let status = writeData(data, service: service, group: group)
        // Unsigned simulator builds have no Keychain group entitlement.
        if status == errSecMissingEntitlement, group != nil { return writeData(data, service: service, group: nil) == errSecSuccess }
        return status == errSecSuccess
    }

    @discardableResult public static func delete() -> Bool {
        #if targetEnvironment(simulator)
        if isolatedPreview { previewConnection = nil; return true }
        #endif
        var ok = delete(service: service, group: SharedStorage.appGroup) && delete(service: service, group: nil)
        for legacy in legacyServices { ok = delete(service: legacy, group: nil) && ok }
        return ok
    }

    private static func decode(_ data: Data) -> ConnectionSettings? {
        guard let config = try? JSONDecoder().decode(ConnectionSettings.self, from: data), config.url != nil else { return nil }
        return config
    }

    private static func query(service: String, group: String?) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        if let group { query[kSecAttrAccessGroup as String] = group }
        return query
    }

    private static func readData(service: String, group: String?) -> Data? {
        var query = query(service: service, group: group)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func writeData(_ data: Data, service: String, group: String?) -> OSStatus {
        let query = query(service: service, group: group)
        let values: [String: Any] = [kSecValueData as String: data,
                                     kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        guard status == errSecItemNotFound else { return status }
        return SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
    }

    private static func delete(service: String, group: String?) -> Bool {
        let status = SecItemDelete(query(service: service, group: group) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound || status == errSecMissingEntitlement
    }
}
