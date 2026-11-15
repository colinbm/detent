import Observation
import UIKit
import UniformTypeIdentifiers

/// A problem to show in an alert.
struct Problem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

/// The iOS app keeps every account in iCloud Keychain, the same items the Mac app uses when
/// "Sync with iCloud Keychain" is on. There is no local-only store to reconcile: iCloud
/// Keychain items stay on this device even when iCloud Keychain is turned off.
@Observable final class AccountsModel {
    var accounts: [Account] = []
    var problem: Problem?
    /// What AutoFill was last told, so it is only told again when something changed.
    private var registered: [Account]?

    /// `reportingFailure` is off for background refreshes, which would otherwise repeat the alert.
    func reload(reportingFailure: Bool = true) {
        #if DEBUG
        if let demo = Self.demoAccounts { accounts = demo; return }
        #endif
        do {
            accounts = try CloudStore.load().accounts
            if accounts != registered {
                registered = accounts
                let accounts = accounts
                Task { await AutoFillCodes.register(accounts) }
            }
        } catch {
            if reportingFailure { problem = Problem(title: "Accounts could not be loaded", detail: error.localizedDescription) }
        }
    }

    #if DEBUG
    /// Launching with `-DetentDemo YES` shows these made-up accounts instead of the keychain's,
    /// for App Store screenshots. Debug builds only.
    static let demoAccounts: [Account]? = {
        guard UserDefaults.standard.bool(forKey: "DetentDemo") else { return nil }
        let entries: [(String, String)] = [
            ("GitHub", "octocat"), ("Google", "jo.bloggs@gmail.com"), ("Amazon.com", "jo.bloggs@gmail.com"),
            ("AWS", "jo@example.com"), ("Cloudflare", "jo@example.com"), ("Dropbox", "jo.bloggs@gmail.com"),
            ("1Password", "Jo Bloggs"), ("Stripe", "jo@example.com"), ("Microsoft", "jo@outlook.com"),
            ("Discord", "jobloggs"),
        ]
        let sites = ["GitHub": ["github.com"], "Google": ["google.com", "accounts.google.com"],
                     "Amazon.com": ["amazon.com", "amazon.co.uk"], "AWS": ["aws.amazon.com", "signin.aws.amazon.com"]]
        return entries.enumerated().map { index, entry in
            var account = Account(issuer: entry.0, name: entry.1,
                                  secret: Data((0..<20).map { UInt8(($0 * 37 + index * 101) % 256) }))
            account.setDomains(sites[entry.0] ?? [])
            return account
        }
    }()
    #endif

    /// Saves `account`, replacing any account with the same issuer and name, as the Mac app does.
    private func store(_ account: Account) throws {
        var account = account
        if let existing = accounts.first(where: { $0.issuer == account.issuer && $0.name == account.name }) {
            account.id = existing.id
            account.sites = SiteRecord.merge(account.sites, existing.sites)
        }
        try CloudStore.save(account)
        reload()
    }

    /// Adds the accounts described by QR code payloads. Reports anything that is not one.
    func addScanned(_ payloads: [String]) {
        let uris = payloads.filter { $0.lowercased().hasPrefix("otpauth://") }
        guard !uris.isEmpty else {
            problem = Problem(title: "No account added", detail: payloads.isEmpty
                ? "No QR code found in the image."
                : "The QR code is not a 2FA setup code.")
            return
        }
        for uri in uris {
            do {
                try store(Account(otpauthURI: uri))
            } catch {
                problem = Problem(title: "An account could not be added", detail: error.localizedDescription)
            }
        }
    }

    /// Adds an account from an otpauth:// URI or base32 secret key. Returns why it failed, or
    /// nil if it worked, so the entry form can show the reason without closing.
    func addPasted(_ string: String, name: String) -> String? {
        do {
            try store(Account(pasted: string, name: name))
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Makes `domains` the sites AutoFill offers `account` on.
    func setSites(_ domains: [String], for account: Account) {
        var account = account
        account.setDomains(domains)
        do {
            try CloudStore.save(account)
        } catch {
            problem = Problem(title: "The sites could not be saved", detail: error.localizedDescription)
        }
        reload()
    }

    func remove(_ account: Account) {
        do {
            try CloudStore.remove(id: account.id)
        } catch {
            problem = Problem(title: "The account could not be deleted", detail: error.localizedDescription)
        }
        reload()
    }

    /// Copies the current code. It expires from the clipboard after two minutes, long after the
    /// code itself has stopped working.
    func copyCode(for account: Account) {
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: account.code()]],
            options: [.expirationDate: Date().addingTimeInterval(120)]
        )
    }
}
