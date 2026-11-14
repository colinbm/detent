import AuthenticationServices

/// What AutoFill knows of Detent's accounts: one identity per account and site, so the system can
/// offer the right code above the keyboard. Codes themselves are only ever handed over on request.
nonisolated enum AutoFillCodes {
    /// Replaces AutoFill's list with `accounts`' sites. Does nothing unless Detent is turned on
    /// in Settings › General › AutoFill & Passwords.
    static func register(_ accounts: [Account]) async {
        let store = ASCredentialIdentityStore.shared
        guard await store.state().isEnabled else { return }
        let identities: [any ASCredentialIdentity] = accounts.flatMap { account in
            account.domains.map { domain in
                ASOneTimeCodeCredentialIdentity(
                    serviceIdentifier: ASCredentialServiceIdentifier(identifier: domain, type: .domain),
                    label: account.label,
                    recordIdentifier: account.id.uuidString)
            }
        }
        try? await store.replaceCredentialIdentities(identities)
    }
}
