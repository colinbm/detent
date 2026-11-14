import Foundation

/// Where the AutoFill extension finds accounts and records the sites it learns.
nonisolated enum ExtensionAccounts {
    #if os(iOS)
    // The iOS app keeps every account in iCloud Keychain, which the extension shares.
    static func load() -> [Account] {
        (try? CloudStore.load().accounts) ?? []
    }

    static func save(_ account: Account) throws {
        try CloudStore.save(account)
    }
    #else
    // The Mac app's own store is a login keychain item this sandboxed extension cannot read, so
    // the app keeps a copy in the shared keychain group. A site learnt here goes into that copy,
    // and the app picks it up from there, sharing it with iCloud too when sync is on.
    static func load() -> [Account] {
        (try? AutoFillCopy.load()) ?? []
    }

    static func save(_ account: Account) throws {
        try AutoFillCopy.update(account)
        DistributedNotificationCenter.default().postNotificationName(
            AccountStore.changedNotification, object: nil, userInfo: nil, deliverImmediately: true)
    }
    #endif
}
