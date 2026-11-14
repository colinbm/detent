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

    /// Saves `account`, replacing any account with the same issuer and name, as the Mac app does.
    private func store(_ account: Account) throws {
        var account = account
        if let existing = accounts.first(where: { $0.issuer == account.issuer && $0.name == account.name }) {
            account.id = existing.id
            account.domains = Domain.union(account.domains, existing.domains)
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
