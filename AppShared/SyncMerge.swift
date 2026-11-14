import Foundation

/// The rules for combining this Mac's accounts with iCloud's. Kept free of keychain calls.
nonisolated enum SyncMerge {
    /// What this Mac should hold, given what iCloud currently shows.
    ///
    /// iCloud's accounts win. A local account iCloud does not show is kept unless iCloud says it
    /// was deleted: "not shown" can just mean iCloud Keychain is off or has not caught up, and
    /// only a deletion record proves the account is really gone.
    ///
    /// The one exception is `sites`, merged record by record so the latest change to each site
    /// wins: the command line tool records sites in the local copy only, and two devices may
    /// each change a site before hearing of the other's change.
    static func reconcile(local: [Account], cloud: [Account], deleted: Set<Account.ID>) -> [Account] {
        let localByID = Dictionary(local.map { ($0.id, $0) }) { first, _ in first }
        let merged = cloud.map { account in
            var account = account
            if let mine = localByID[account.id] { account.sites = SiteRecord.merge(account.sites, mine.sites) }
            return account
        }
        let cloudIDs = Set(cloud.map(\.id))
        let localOnly = local.filter { !cloudIDs.contains($0.id) && !deleted.contains($0.id) }
        return sorted(merged + localOnly)
    }

    /// The merged accounts with site changes iCloud's copy lacks, and so need uploading.
    static func newerSites(merged: [Account], cloud: [Account]) -> [Account] {
        let cloudByID = Dictionary(cloud.map { ($0.id, $0) }) { first, _ in first }
        return merged.filter { account in
            guard let theirs = cloudByID[account.id] else { return false }
            return account.sites != theirs.sites
        }
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
        b.sites = a.sites
        return a == b
    }
}
