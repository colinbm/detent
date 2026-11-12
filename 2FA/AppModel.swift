import AppKit
import Observation

@Observable final class AppModel {
    var accounts: [Account] = []
    var message: String?
    var isScanning = false

    func reload() {
        do {
            accounts = try AccountStore.load()
        } catch {
            message = error.localizedDescription
        }
    }

    /// Looks for 2FA QR codes on every display and adds the accounts they describe.
    func scanScreen() async {
        isScanning = true
        defer { isScanning = false }

        let payloads: [String]
        do {
            payloads = try await ScreenScanner.qrPayloads()
        } catch {
            message = CGPreflightScreenCaptureAccess()
                ? error.localizedDescription
                : "Allow 2FA under System Settings › Privacy & Security › Screen & System Audio Recording, then scan again."
            return
        }

        let uris = payloads.filter { $0.lowercased().hasPrefix("otpauth://") }
        guard !uris.isEmpty else {
            message = payloads.isEmpty
                ? "No QR code found on screen."
                : "The QR code on screen is not a 2FA setup code."
            return
        }

        var added: [String] = []
        var failure: String?
        for uri in uris {
            do {
                let account = try Account(otpauthURI: uri)
                try AccountStore.add(account)
                added.append(account.label)
            } catch {
                failure = error.localizedDescription
            }
        }
        reload()
        message = failure ?? "Added \(added.joined(separator: ", "))."
    }

    func remove(_ account: Account) {
        do {
            try AccountStore.remove(id: account.id)
            message = nil
        } catch {
            message = error.localizedDescription
        }
        reload()
    }

    func copyCode(for account: Account) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(account.code(), forType: .string)
        message = "Copied code for \(account.label)."
    }
}
