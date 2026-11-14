import Foundation

/// The rules for combining this Mac's accounts with iCloud's. Kept free of keychain calls.
nonisolated enum SyncMerge {
    /// What this Mac should hold, given what iCloud currently shows.
    ///
    /// iCloud's accounts win. A local account iCloud does not show is kept unless iCloud says it
    /// was deleted: "not shown" can just mean iCloud Keychain is off or has not caught up, and
    /// only a deletion record proves the account is really gone.
    static func reconcile(local: [Account], cloud: [Account], deleted: Set<Account.ID>) -> [Account] {
        let cloudIDs = Set(cloud.map(\.id))
        let localOnly = local.filter { !cloudIDs.contains($0.id) && !deleted.contains($0.id) }
        return sorted(cloud + localOnly)
    }

    /// The accounts to upload when sync is first turned on, so that nothing on this Mac is lost.
    ///
    /// An account already in iCloud (same ID, or identical in every detail) is not uploaded
    /// again. One that shares an issuer and name with a different iCloud account is uploaded
    /// under a numbered name, so both are kept and the command line tool can tell them apart.
    static func uploadsWhenEnabling(local: [Account], cloud: [Account], deleted: Set<Account.ID>) -> [Account] {
        var known = cloud
        var uploads: [Account] = []
        for var account in local {
            if deleted.contains(account.id) || known.contains(where: { $0.id == account.id }) { continue }
            if known.contains(where: { sameDetails($0, account) }) { continue }

            let original = account.name
            var number = 2
            while known.contains(where: { $0.issuer == account.issuer && $0.name == account.name }) {
                account.name = "\(original) (\(number))"
                number += 1
            }
            known.append(account)
            uploads.append(account)
        }
        return uploads
    }

    static func sorted(_ accounts: [Account]) -> [Account] {
        accounts.sorted {
            let order = $0.label.localizedCaseInsensitiveCompare($1.label)
            return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
        }
    }

    private static func sameDetails(_ a: Account, _ b: Account) -> Bool {
        var b = b
        b.id = a.id
        return a == b
    }
}
