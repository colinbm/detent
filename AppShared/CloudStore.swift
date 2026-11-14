import Foundation
import Security

/// Accounts in iCloud Keychain: one synchronizable item per account, so devices adding
/// different accounts at the same time cannot overwrite each other.
///
/// Removing an account leaves a deletion record in its place, so that other devices can tell
/// "deleted" apart from "not synced yet".
///
/// Only the Mac and iOS apps can use this store, because it needs the keychain access group
/// entitlement, which both carry. The command line tool reads the local copy that the Mac app's
/// `AppModel` keeps in step with it.
nonisolated enum CloudStore {
    private static let baseQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.colinbm.detent.account",
        kSecUseDataProtectionKeychain as String: true,
        kSecAttrSynchronizable as String: true,
    ]

    /// What replaces an account's data once it has been removed.
    private struct Deleted: Codable {
        var deleted = true
    }

    /// The accounts iCloud Keychain currently shows, and the IDs of those known to be deleted.
    static func load() throws -> (accounts: [Account], deleted: Set<Account.ID>) {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return ([], []) }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw KeychainError(status: status)
        }

        var accounts: [Account] = []
        var deleted: Set<Account.ID> = []
        for item in items {
            guard let data = item[kSecValueData as String] as? Data else { continue }
            if let account = try? JSONDecoder().decode(Account.self, from: data) {
                accounts.append(account)
            } else if (try? JSONDecoder().decode(Deleted.self, from: data)) != nil,
                      let id = (item[kSecAttrAccount as String] as? String).flatMap(UUID.init(uuidString:)) {
                deleted.insert(id)
            }
        }
        return (SyncMerge.sorted(accounts), deleted)
    }

    static func save(_ account: Account) throws {
        try write(JSONEncoder().encode(account), id: account.id, label: "Detent: \(account.label)")
    }

    /// Replaces the account with a deletion record, which syncs like any other change.
    static func remove(id: Account.ID) throws {
        try write(JSONEncoder().encode(Deleted()), id: id, label: "Detent: deleted account")
    }

    private static func write(_ data: Data, id: Account.ID, label: String) throws {
        var query = baseQuery
        query[kSecAttrAccount as String] = id.uuidString

        let changes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrLabel as String: label,
        ]
        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(changes) { $1 }
            // Items must be readable off-device to sync, so not a "this device only" class.
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
}
