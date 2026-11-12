import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var isEnteringKey = false
    @State private var keyText = ""
    @State private var nameText = ""

    private var keyIsURI: Bool {
        keyText.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("otpauth://")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.accounts.isEmpty {
                Text("No accounts yet. Put a 2FA setup QR code anywhere on screen and scan, or enter its key.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(model.accounts) { account in
                                AccountRow(account: account, date: timeline.date) {
                                    model.copyCode(for: account)
                                }
                                .contextMenu {
                                    Button("Copy Code") { model.copyCode(for: account) }
                                    Button("Delete “\(account.label)”", role: .destructive) { model.remove(account) }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 420)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            if let message = model.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            if isEnteringKey {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Secret key or otpauth:// link", text: $keyText)
                        Button("Paste") {
                            keyText = NSPasteboard.general.string(forType: .string)?
                                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        }
                    }
                    if !keyIsURI {
                        TextField("Name, e.g. GitHub", text: $nameText)
                    }
                    HStack {
                        Spacer()
                        Button("Cancel") { endKeyEntry() }
                        Button("Add") {
                            if model.addPasted(keyText, name: nameText) { endKeyEntry() }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(keyText.isEmpty)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            }

            HStack {
                Button {
                    Task { await model.scanScreen() }
                } label: {
                    Label("Scan Screen", systemImage: "qrcode.viewfinder")
                }
                .disabled(model.isScanning)
                .help("Find a 2FA QR code anywhere on screen")

                Button {
                    isEnteringKey = true
                } label: {
                    Label("Enter Key", systemImage: "keyboard")
                }
                .disabled(isEnteringKey)
                .help("Paste a secret key or otpauth:// link")

                Spacer()

                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .padding(12)
        }
        .frame(width: 320)
        .onAppear { model.reload() }
    }
}

extension ContentView {
    private func endKeyEntry() {
        isEnteringKey = false
        keyText = ""
        nameText = ""
    }
}

private struct AccountRow: View {
    let account: Account
    let date: Date
    let copy: () -> Void

    var body: some View {
        let remaining = TOTP.secondsRemaining(period: account.period, at: date)
        let code = account.code(at: date)
        let half = code.index(code.startIndex, offsetBy: code.count / 2)

        Button(action: copy) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.issuer.isEmpty ? account.name : account.issuer)
                        .font(.headline)
                        .lineLimit(1)
                    if !account.issuer.isEmpty && !account.name.isEmpty {
                        Text(account.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text("\(code[..<half]) \(code[half...])")
                    .font(.title2.monospacedDigit().weight(.medium))
                    .foregroundStyle(remaining <= 5 ? .red : .primary)
                ProgressView(value: remaining, total: Double(account.period))
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click to copy")
        .accessibilityLabel("\(account.label), code \(code)")
    }
}
