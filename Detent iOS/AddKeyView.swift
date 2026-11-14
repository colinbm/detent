import SwiftUI

/// Adds an account from a pasted otpauth:// link or a bare secret key.
struct AddKeyView: View {
    let model: AccountsModel
    @Environment(\.dismiss) private var dismiss
    @State private var keyText = ""
    @State private var nameText = ""
    @State private var error: String?

    private var keyIsURI: Bool {
        keyText.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("otpauth://")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Secret key or otpauth:// link", text: $keyText, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .fontDesign(.monospaced)
                    PasteButton(payloadType: String.self) { strings in
                        keyText = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    }
                } footer: {
                    Text("Sites that show a QR code usually offer the key as text too, often behind a link such as “Can’t scan it?”.")
                }
                if !keyIsURI {
                    Section {
                        TextField("Name, e.g. GitHub", text: $nameText)
                            .autocorrectionDisabled()
                    }
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Enter Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        error = model.addPasted(keyText, name: nameText)
                        if error == nil { dismiss() }
                    }
                    .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: keyText) { error = nil }
        }
    }
}
