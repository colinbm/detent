import AuthenticationServices
import SwiftUI
#if os(iOS)
private typealias HostingController = UIHostingController
#else
private typealias HostingController = NSHostingController
#endif

/// Detent's AutoFill extension: supplies verification codes to Safari and other apps.
final class CredentialProviderViewController: ASCredentialProviderViewController {
    /// AutoFill offered one of the identities in `AutoFillCodes` above the keyboard and the user
    /// tapped it, so the account is known and the code can go straight in.
    override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        guard credentialRequest.type == .oneTimeCode,
              let id = credentialRequest.credentialIdentity.recordIdentifier.flatMap(UUID.init(uuidString:)),
              let account = ExtensionAccounts.load().first(where: { $0.id == id })
        else {
            extensionContext.cancelRequest(withError: ASExtensionError(.credentialIdentityNotFound))
            return
        }
        Task { await complete(with: account) }
    }

    /// The system wants interface for a request it could not complete silently.
    override func prepareInterfaceToProvideCredential(for credentialRequest: any ASCredentialRequest) {
        guard credentialRequest.type == .oneTimeCode else {
            showUnsupported()
            return
        }
        provideCredentialWithoutUserInteraction(for: credentialRequest)
    }

    // Detent has no passwords or passkeys, but Safari can still offer it on those fields. Every
    // request needs an answer, or Safari waits on it indefinitely, so explain and step aside.

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        showUnsupported()
    }

    override func prepareCredentialList(
        for serviceIdentifiers: [ASCredentialServiceIdentifier],
        requestParameters: ASPasskeyCredentialRequestParameters
    ) {
        showUnsupported()
    }

    /// The user chose Detent from the AutoFill menu, so let them pick the account.
    override func prepareOneTimeCodeCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        let accounts = ExtensionAccounts.load()
        // Most specific first, such as [m.example.com, example.com]. The broadest is the one
        // worth remembering, since it covers the others.
        let hosts = serviceIdentifiers.compactMap { Domain.host(from: $0.identifier) }
        show(AccountPicker(accounts: accounts, hosts: hosts) { [weak self] account in
            Task { await self?.complete(with: account, learning: hosts.last, among: accounts) }
        } cancel: { [weak self] in
            self?.extensionContext.cancelRequest(withError: ASExtensionError(.userCanceled))
        })
    }

    /// Called when Detent is turned on in Settings: a good moment to tell AutoFill the sites.
    override func prepareInterfaceForExtensionConfiguration() {
        let accounts = ExtensionAccounts.load()
        Task {
            // Settings shows a blank sheet until this completes, so never wait long on the store.
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await AutoFillCodes.register(accounts) }
                group.addTask { try? await Task.sleep(for: .seconds(2)) }
                await group.next()
                group.cancelAll()
            }
            extensionContext.completeExtensionConfigurationRequest()
        }
    }

    private func complete(with account: Account, learning host: String? = nil, among accounts: [Account] = []) async {
        if let host {
            var account = account
            if account.remember(domain: host), (try? ExtensionAccounts.save(account)) != nil {
                await AutoFillCodes.register(accounts.map { $0.id == account.id ? account : $0 })
            }
        }
        // A code in its last moments may expire before the form is sent. Wait for the next.
        let remaining = TOTP.secondsRemaining(period: account.period)
        if remaining < 3 { try? await Task.sleep(for: .seconds(remaining + 0.2)) }
        _ = await extensionContext.completeOneTimeCodeRequest(using: ASOneTimeCodeCredential(code: account.code()))
    }

    private func showUnsupported() {
        show(Unsupported { [weak self] in
            self?.extensionContext.cancelRequest(withError: ASExtensionError(.userCanceled))
        }, size: CGSize(width: 340, height: 200))
    }

    private func show(_ view: some View, size: CGSize = CGSize(width: 420, height: 460)) {
        let host = HostingController(rootView: view)
        addChild(host)
        host.view.frame = self.view.bounds
        #if os(iOS)
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(host.view)
        host.didMove(toParent: self)
        #else
        host.view.autoresizingMask = [.width, .height]
        self.view.addSubview(host.view)
        preferredContentSize = size
        #endif
    }
}

/// Shown when Detent is asked for something it does not have, such as a password.
private struct Unsupported: View {
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.rotation")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Detent only fills verification codes")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Choose Detent from AutoFill on the field that asks for the code.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("OK", action: dismiss)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
