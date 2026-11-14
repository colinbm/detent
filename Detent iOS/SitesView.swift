import SwiftUI

/// Lists the sites AutoFill offers an account on, for removing wrong ones and adding others.
struct SitesView: View {
    let model: AccountsModel
    let accountID: Account.ID
    @Environment(\.dismiss) private var dismiss
    @State private var newSite = ""
    @State private var error: String?
    @FocusState private var addingSite: Bool

    private var account: Account? { model.accounts.first { $0.id == accountID } }

    var body: some View {
        NavigationStack {
            Form {
                if let account {
                    Section {
                        if account.domains.isEmpty {
                            Text("No sites yet")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(account.domains, id: \.self) { domain in
                            Text(domain)
                        }
                        .onDelete { offsets in
                            let domains = account.domains
                            model.setSites(domains.enumerated().filter { !offsets.contains($0.offset) }.map(\.element), for: account)
                        }
                    } header: {
                        Text(account.label)
                    } footer: {
                        Text("AutoFill offers this account’s code on these sites and their subdomains. Changes reach your other devices through iCloud Keychain.")
                    }

                    Section {
                        HStack {
                            TextField("Add a site, e.g. github.com", text: $newSite)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($addingSite)
                                .submitLabel(.done)
                                .onSubmit(add)
                            Button("Add", action: add)
                                .disabled(newSite.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } footer: {
                        if let error {
                            Text(error).foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Sites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: newSite) { error = nil }
        }
    }

    private func add() {
        guard let account else { return }
        guard let host = Domain.host(from: newSite) else {
            error = "Enter a site’s address, such as github.com."
            return
        }
        model.setSites(account.domains + [host], for: account)
        newSite = ""
        // Ready for the next one.
        addingSite = true
    }
}
