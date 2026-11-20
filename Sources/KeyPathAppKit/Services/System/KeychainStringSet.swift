import Foundation
import KeyPathCore
import Security

/// A set of strings kept in one login-Keychain item that only KeyPath can read
/// without asking the user. Unlike UserDefaults, another process cannot add to
/// it silently, so it holds the user's security choices.
@MainActor
final class KeychainStringSet {
    /// Inject Security operations for deterministic tests; production uses the login Keychain.
    @MainActor
    struct Access {
        var read: ([String: Any]) -> (OSStatus, Data?)
        var update: ([String: Any], Data) -> OSStatus
        var add: ([String: Any], Data) -> OSStatus
        var delete: ([String: Any]) -> OSStatus

        static let system = Access(
            read: { query in
                var result: AnyObject?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                return (status, result as? Data)
            },
            update: { query, data in
                SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            },
            add: { query, data in
                var add = query
                add[kSecValueData as String] = data
                add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                return SecItemAdd(add as CFDictionary, nil)
            },
            delete: { SecItemDelete($0 as CFDictionary) }
        )
    }

    private let access: Access
    private let service: String
    private let account: String
    private var cache: Set<String>?

    init(service: String = "com.keypath.app", account: String, access: Access = .system) {
        self.access = access
        self.service = service
        self.account = account
    }

    var members: Set<String> {
        load()
    }

    /// Adds a member. Returns false, and changes nothing, when the Keychain refuses the write.
    @discardableResult
    func insert(_ member: String) -> Bool {
        // Writing after a failed read would replace the stored set with one member.
        guard var next = loadForWrite() else { return false }
        guard next.insert(member).inserted else { return true }
        return save(next)
    }

    /// Removes a member. Returns false, and changes nothing, when the Keychain refuses the write.
    @discardableResult
    func remove(_ member: String) -> Bool {
        guard var next = loadForWrite() else { return false }
        guard next.remove(member) != nil else { return true }
        return save(next)
    }

    /// Removes the item. Returns false, and keeps the cached members, when the Keychain refuses.
    @discardableResult
    func removeAll() -> Bool {
        let status = access.delete(baseQuery)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            AppLogger.shared.log("⚠️ [Keychain] Could not delete \(account) (status \(status))")
            return false
        }
        cache = []
        return true
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// The stored members, or nil when the Keychain could not be read.
    private func loadForWrite() -> Set<String>? {
        let members = load()
        return lastReadFailed ? nil : members
    }

    private var lastReadFailed = false

    /// A failed read is not cached, so the next read tries again.
    private func load() -> Set<String> {
        if let cache { return cache }
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = access.read(query)
        var members: Set<String> = []
        if status == errSecSuccess {
            // Undecodable contents are treated as empty, so a damaged item can be
            // replaced; refusing every write would make "Always Allow" impossible.
            if let data, let list = try? JSONDecoder().decode([String].self, from: data) {
                members = Set(list)
            } else {
                AppLogger.shared.log("⚠️ [Keychain] \(account) could not be decoded; starting fresh")
            }
        } else if status != errSecItemNotFound {
            AppLogger.shared.log("⚠️ [Keychain] Could not read \(account) (status \(status))")
            lastReadFailed = true
            return []
        }
        lastReadFailed = false
        cache = members
        return members
    }

    private func save(_ members: Set<String>) -> Bool {
        guard let data = try? JSONEncoder().encode(members.sorted()) else { return false }
        var status = access.update(baseQuery, data)
        if status == errSecItemNotFound {
            status = access.add(baseQuery, data)
        }
        guard status == errSecSuccess else {
            AppLogger.shared.log("⚠️ [Keychain] Could not save \(account) (status \(status))")
            return false
        }
        cache = members
        return true
    }
}
