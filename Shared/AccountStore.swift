import Foundation
import Security

nonisolated struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
        return "Keychain: \(message)"
    }
}

/// All accounts live in a single login-keychain item (a JSON array), shared by the app and
/// the command line tool. One item means one "Always Allow" per program rather than one per account.
nonisolated enum AccountStore {
    /// Posted, without a payload, by the command line tool after it changes accounts, so that
    /// a running app reloads them and copies the change to iCloud straight away.
    static let changedNotification = Notification.Name("com.colinbm.detent.accounts-changed")

    private static let baseQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Detent",
        kSecAttrAccount as String: "accounts",
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
        if accounts.isEmpty {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }

        let data = try JSONEncoder().encode(accounts)
        var status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "Detent accounts"
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    /// Adds `account`, replacing any existing account with the same issuer and name.
    static func add(_ account: Account) throws {
        var accounts = try load()
        if let index = accounts.firstIndex(where: { $0.issuer == account.issuer && $0.name == account.name }) {
            var updated = account
            updated.id = accounts[index].id
            updated.sites = SiteRecord.merge(account.sites, accounts[index].sites)
            accounts[index] = updated
        } else {
            accounts.append(account)
        }
        try save(accounts)
    }

    /// Records that the account with `id` is used on `domain`; see `Account.remember`.
    /// Returns whether anything changed.
    @discardableResult
    static func remember(domain: String, forAccount id: Account.ID, overridingRemoval: Bool) throws -> Bool {
        var accounts = try load()
        guard let index = accounts.firstIndex(where: { $0.id == id }),
              accounts[index].remember(domain: domain, overridingRemoval: overridingRemoval)
        else { return false }
        try save(accounts)
        return true
    }

    static func remove(id: Account.ID) throws {
        var accounts = try load()
        accounts.removeAll { $0.id == id }
        try save(accounts)
    }
}
