import ImageIO
import PhotosUI
import SwiftUI
import VisionKit

struct AccountsView: View {
    @Bindable var model: AccountsModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var search = ""
    @State private var isScanning = false
    @State private var isPickingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var isEnteringKey = false
    @State private var pendingDeletion: Account?
    @State private var editingSites: Account?
    @State private var copied: Account.ID?
    @State private var copyCount = 0

    private var cameraAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    private var shown: [Account] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? model.accounts : model.accounts.filter {
            $0.label.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.accounts.isEmpty {
                    ContentUnavailableView {
                        Label("No Accounts", systemImage: "lock.rotation")
                    } description: {
                        Text("Add an account with the + button. Accounts from Detent on your Mac appear here when Sync with iCloud Keychain is on there.")
                    }
                } else {
                    list
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                brand
                addMenu
            }
        }
        .overlay(alignment: .bottom) { copiedBanner }
        // Keep codes out of the app switcher snapshot.
        .overlay {
            if scenePhase != .active {
                Rectangle().fill(.background).ignoresSafeArea()
            }
        }
        .sensoryFeedback(.success, trigger: copyCount)
        .fullScreenCover(isPresented: $isScanning) {
            QRScannerView { payload in
                isScanning = false
                model.addScanned([payload])
            } cancel: {
                isScanning = false
            }
        }
        .photosPicker(isPresented: $isPickingPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            Task { await addFromPhoto(item) }
        }
        .sheet(isPresented: $isEnteringKey) {
            AddKeyView(model: model)
        }
        .sheet(item: $editingSites) { account in
            SitesView(model: model, accountID: account.id)
        }
        .confirmationDialog(
            "Delete “\(pendingDeletion?.label ?? "")”?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { account in
            Button("Delete Account", role: .destructive) { model.remove(account) }
        } message: { _ in
            Text("It is also removed from your other devices that sync Detent through iCloud Keychain.")
        }
        .alert(model.problem?.title ?? "", isPresented: Binding(
            get: { model.problem != nil }, set: { if !$0 { model.problem = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(model.problem?.detail ?? "")
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { model.reload() }
        }
        // Nothing announces changes arriving from other devices, so check now and then.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if scenePhase == .active { model.reload(reportingFailure: false) }
            }
        }
    }

    private var list: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            List {
                ForEach(shown) { account in
                    AccountRow(account: account, date: timeline.date, copied: copied == account.id) {
                        copy(account)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = account }
                    }
                    .swipeActions(edge: .leading) {
                        Button("Sites", systemImage: "globe") { editingSites = account }
                            .tint(.accentColor)
                    }
                    .contextMenu {
                        Button("Copy Code", systemImage: "doc.on.doc") { copy(account) }
                        Button("Sites…", systemImage: "globe") { editingSites = account }
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = account }
                    }
                }
            }
            .overlay {
                if shown.isEmpty { ContentUnavailableView.search(text: search) }
            }
        }
        .searchable(text: $search, prompt: "Search accounts")
        .refreshable { model.reload() }
    }

    /// The app's icon and name, small, opposite the add button.
    @ToolbarContentBuilder private var brand: some ToolbarContent {
        // Toolbars show only the icon of a label unless told otherwise.
        let label = Label {
            Text("Detent")
                .font(.headline)
        } icon: {
            Image("Logo")
                .resizable()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .labelStyle(.titleAndIcon)
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)

        if #available(iOS 26.0, *) {
            // A label, not a button, so no glass background behind it.
            ToolbarItem(placement: .topBarLeading) { label }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { label }
        }
    }

    @ToolbarContentBuilder private var addMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if cameraAvailable {
                    Button("Scan QR Code", systemImage: "qrcode.viewfinder") { isScanning = true }
                }
                Button("Choose Photo or Screenshot", systemImage: "photo") { isPickingPhoto = true }
                Button("Enter Key", systemImage: "keyboard") { isEnteringKey = true }
            } label: {
                Label("Add Account", systemImage: "plus")
            }
        }
    }

    @ViewBuilder private var copiedBanner: some View {
        if copied != nil {
            Label("Copied", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.thickMaterial, in: Capsule())
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func copy(_ account: Account) {
        model.copyCode(for: account)
        copyCount += 1
        let count = copyCount
        withAnimation { copied = account.id }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copyCount == count { withAnimation { copied = nil } }
        }
    }

    private func addFromPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            model.problem = Problem(title: "No account added", detail: "The image could not be opened.")
            return
        }
        do {
            model.addScanned(try QRDecoder.payloads(in: image))
        } catch {
            model.problem = Problem(title: "The image could not be scanned", detail: error.localizedDescription)
        }
    }
}
