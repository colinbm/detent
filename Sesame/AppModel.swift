import AppKit
import Observation
import ServiceManagement

@Observable final class AppModel {
    var accounts: [Account] = []
    var message: String?
    var isScanning = false

    /// Whether iCloud Keychain is the primary store. When it is, the local keychain item is a
    /// copy kept for the command line tool, which cannot reach iCloud Keychain itself.
    private(set) var syncEnabled = UserDefaults.standard.bool(forKey: "iCloudSync")
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    init() {
        // Nothing announces changes arriving from other devices, so refresh the local copy
        // periodically: the command line tool only ever sees that copy.
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.syncEnabled else { return }
                self.reload()
            }
        }
    }

    func reload() {
        do {
            let local = try AccountStore.load()
            guard syncEnabled else {
                accounts = local
                return
            }
            let cloud = try CloudStore.load()
            let merged = SyncMerge.reconcile(local: local, cloud: cloud.accounts, deleted: cloud.deleted)
            if merged != local { try AccountStore.save(merged) }
            accounts = merged
        } catch {
            message = error.localizedDescription
        }
    }

    /// Saves `account` to the primary store and the local copy, replacing any account
    /// with the same issuer and name.
    private func store(_ account: Account) throws {
        var account = account
        if let existing = accounts.first(where: { $0.issuer == account.issuer && $0.name == account.name }) {
            account.id = existing.id
        }
        if syncEnabled { try CloudStore.save(account) }
        try AccountStore.add(account)
    }

    func setSync(_ enabled: Bool) {
        if enabled {
            do {
                let cloud = try CloudStore.load()
                let uploads = SyncMerge.uploadsWhenEnabling(
                    local: try AccountStore.load(), cloud: cloud.accounts, deleted: cloud.deleted)
                for account in uploads { try CloudStore.save(account) }
                // Everything on this Mac is now in iCloud, so the local copy can match it exactly.
                // This also drops local duplicates and picks up any numbered names.
                try AccountStore.save(CloudStore.load().accounts)
            } catch {
                message = "iCloud sync could not be turned on. \(error.localizedDescription)"
                return
            }
            message = "Syncing with iCloud Keychain."
        } else {
            message = "iCloud sync is off. Accounts stay on this Mac and in iCloud."
        }
        syncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "iCloudSync")
        reload()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            message = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
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
                try store(account)
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
            try store(account)
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

    /// Writes every account to a passphrase-encrypted file the user chooses.
    func exportAccounts() {
        guard !accounts.isEmpty else {
            message = "There are no accounts to export."
            return
        }
        guard let passphrase = askPassphrase(
            title: "Choose a passphrase for the backup",
            text: "You will need it to import the backup. It cannot be recovered if you forget it.",
            confirm: true
        ) else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Sesame Accounts.\(Backup.fileExtension)"
        panel.canCreateDirectories = true
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try Backup.encrypt(accounts, passphrase: passphrase).write(to: url, options: .atomic)
            message = "Exported \(accounts.count) account\(accounts.count == 1 ? "" : "s")."
        } catch {
            message = error.localizedDescription
        }
    }

    /// Adds the accounts in a backup file, replacing any with the same issuer and name.
    func importAccounts() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = "Choose a Sesame backup file."
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let passphrase = askPassphrase(
            title: "Enter the backup's passphrase", text: url.lastPathComponent, confirm: false
        ) else { return }

        do {
            let imported = try Backup.decrypt(Data(contentsOf: url), passphrase: passphrase)
            for account in imported { try store(account) }
            reload()
            message = "Imported \(imported.count) account\(imported.count == 1 ? "" : "s")."
        } catch {
            message = error.localizedDescription
        }
    }

    /// Asks for a passphrase, twice if `confirm`. Returns nil if cancelled, empty or mismatched.
    private func askPassphrase(title: String, text: String, confirm: Bool) -> String? {
        let first = NSSecureTextField(frame: NSRect(x: 0, y: confirm ? 30 : 0, width: 260, height: 24))
        first.placeholderString = "Passphrase"
        let second = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        second.placeholderString = "Repeat passphrase"

        let fields = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: confirm ? 54 : 24))
        fields.addSubview(first)
        if confirm {
            fields.addSubview(second)
            first.nextKeyView = second
        }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.accessoryView = fields
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = first
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let passphrase = first.stringValue
        if passphrase.isEmpty {
            message = "The passphrase cannot be empty."
            return nil
        }
        if confirm && passphrase != second.stringValue {
            message = "The passphrases did not match."
            return nil
        }
        return passphrase
    }

    func remove(_ account: Account) {
        do {
            if syncEnabled { try CloudStore.remove(id: account.id) }
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
