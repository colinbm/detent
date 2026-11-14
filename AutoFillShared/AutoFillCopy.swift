import Foundation
import Security

/// Every account, kept by the Mac app in the keychain group it shares with its AutoFill
/// extension. The app's own store is a login keychain item, which the sandboxed extension
/// cannot read. This copy stays on this Mac: iCloud sync, when on, has its own items.
///
/// The extension writes sites it learns into the copy; the app merges them back on its next
/// reload, so the copy is never the only place a site is kept for long.
nonisolated enum AutoFillCopy {
    private static let baseQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.colinbm.detent.autofill-copy",
        kSecAttrAccount as String: "accounts",
        kSecUseDataProtectionKeychain as String: true,
    ]

    static func load() throws -> [Account] {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return try JSONDecoder().decode([Account].self, from: data)
    }

    static func save(_ accounts: [Account]) throws {
        let data = try JSONEncoder().encode(accounts)
        var status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "Detent accounts for AutoFill"
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    /// Replaces the copy's account with the same ID as `account`.
    static func update(_ account: Account) throws {
        var accounts = try load()
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index] = account
        try save(accounts)
    }
}
