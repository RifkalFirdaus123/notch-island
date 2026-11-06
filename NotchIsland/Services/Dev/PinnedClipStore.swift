import Foundation
import Security

/// Where pinned clipboard items are kept between launches.
protocol PinnedClipStore {
    func load() -> Data?
    func save(_ data: Data)
}

/// Pinned items can be passwords and tokens, so they go in the login
/// Keychain (encrypted) as one generic-password item rather than a file.
///
/// Builds signed ad hoc get a new signature each time, so after rebuilding
/// macOS may ask once whether NotchIsland may read the item.
nonisolated struct KeychainPinnedClipStore: PinnedClipStore {
    var service = "NotchIsland.pinnedClips"
    var account = "pinned"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func save(_ data: Data) {
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "NotchIsland pinned clipboard items"
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            if addStatus != errSecSuccess { NSLog("NotchIsland: Keychain add failed (\(addStatus))") }
        } else if status != errSecSuccess {
            NSLog("NotchIsland: Keychain update failed (\(status))")
        }
    }
}

/// Keeps pins in memory only; for tests.
final class MemoryPinnedClipStore: PinnedClipStore {
    private var data: Data?

    init(data: Data? = nil) { self.data = data }

    func load() -> Data? { data }
    func save(_ data: Data) { self.data = data }
}
