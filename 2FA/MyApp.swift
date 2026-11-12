import SwiftUI

@main struct MyApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("2FA", systemImage: "lock.shield") {
            ContentView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
