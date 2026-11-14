import SwiftUI

/// The list shown when the user picks Detent from the AutoFill menu. Accounts that look like
/// they belong to the site come first.
struct AccountPicker: View {
    let accounts: [Account]
    /// The site asking, most specific first. May be empty.
    let hosts: [String]
    let pick: (Account) -> Void
    let cancel: () -> Void

    @State private var search = ""

    private var site: String? { hosts.last }

    private func filtered(_ list: [Account]) -> [Account] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? list : list.filter { $0.label.localizedCaseInsensitiveContains(query) }
    }

    private var suggested: [Account] { filtered(accounts.filter(isLikely)) }
    private var others: [Account] { filtered(accounts.filter { !isLikely($0) }) }

    /// Whether `account` is known to be used on the site, or is named after it.
    private func isLikely(_ account: Account) -> Bool {
        guard !hosts.isEmpty else { return false }
        if hosts.contains(where: account.matches(host:)) { return true }
        let issuer = account.issuer.lowercased().filter { $0.isLetter || $0.isNumber }
        guard issuer.count >= 3 else { return false }
        return hosts.contains { $0.replacingOccurrences(of: ".", with: "").contains(issuer) }
    }

    var body: some View {
        #if os(iOS)
        NavigationStack {
            list
                .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search accounts")
                .navigationTitle(site ?? "Detent")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: cancel)
                    }
                }
        }
        #else
        VStack(spacing: 0) {
            HStack {
                Text(site ?? "Detent")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                TextField("Search accounts", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            .padding(12)
            list
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(minWidth: 380, minHeight: 420)
        #endif
    }

    private var hint: Text? {
        site.map { Text("Detent remembers the account you choose for \($0) and offers it straight away next time.") }
    }

    private var list: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            List {
                if !suggested.isEmpty {
                    Section {
                        rows(suggested, at: timeline.date)
                    } header: {
                        Text("Suggested")
                    } footer: {
                        if let site, suggested.contains(where: { !$0.matches(host: site) }) { hint }
                    }
                }
                if !others.isEmpty {
                    Section {
                        rows(others, at: timeline.date)
                    } header: {
                        Text(suggested.isEmpty ? "Accounts" : "Other Accounts")
                    } footer: {
                        if suggested.isEmpty { hint }
                    }
                }
            }
            .overlay {
                if accounts.isEmpty {
                    ContentUnavailableView("No Accounts", systemImage: "lock.rotation",
                                           description: Text("Add accounts in the Detent app."))
                } else if suggested.isEmpty && others.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
    }

    private func rows(_ list: [Account], at date: Date) -> some View {
        ForEach(list) { account in
            Button {
                pick(account)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.issuer.isEmpty ? account.name : account.issuer)
                            .font(.headline)
                        if !account.issuer.isEmpty && !account.name.isEmpty {
                            Text(account.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                    Spacer()
                    let code = account.code(at: date)
                    let half = code.index(code.startIndex, offsetBy: code.count / 2)
                    Text("\(code[..<half]) \(code[half...])")
                        .font(.title3.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(account.label)
        }
    }
}
