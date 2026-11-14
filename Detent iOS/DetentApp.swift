import SwiftUI

@main struct DetentApp: App {
    @State private var model = AccountsModel()

    var body: some Scene {
        WindowGroup {
            AccountsView(model: model)
        }
    }
}
