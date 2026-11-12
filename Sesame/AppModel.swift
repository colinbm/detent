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
                : "Allow Sesame under System Settings › Privacy & Security › Screen & System Audio Recording, then scan again."
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

    /// Adds an account from a pasted otpauth:// URI or base32 secret key. Returns whether it worked.
    func addPasted(_ string: String, name: String) -> Bool {
        do {
            let account = try Account(pasted: string, name: name)
            try AccountStore.add(account)
            reload()
            message = "Added \(account.label)."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    /// Shows the terminal command that links the bundled `sesame` tool into /usr/local/bin.
    /// The app is sandboxed and that folder belongs to root, so it cannot create the link itself.
    func installCommandLineTool() {
        let tool = Bundle.main.bundleURL.appending(path: "Contents/Helpers/sesame")
        let alert = NSAlert()

        if FileManager.default.isExecutableFile(atPath: tool.path) {
            let quoted = "'" + tool.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
            let command = "sudo mkdir -p /usr/local/bin && sudo ln -sf \(quoted) /usr/local/bin/sesame"
            alert.messageText = "Install the sesame command"
            alert.informativeText = """
                Paste this into a terminal. It asks for your password, then links sesame into /usr/local/bin:

                \(command)

                Run it again if you move Sesame.
                """
            alert.addButton(withTitle: "Copy Command")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }
        } else {
            alert.messageText = "Command line tool missing"
            alert.informativeText = "This copy of Sesame does not contain the sesame tool."
            NSApp.activate()
            alert.runModal()
        }
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
