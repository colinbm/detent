import SwiftUI

@main struct DetentApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Detent", systemImage: "lock.shield") {
            ContentView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
