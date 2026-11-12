import SwiftUI

@main struct SesameApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Sesame", systemImage: "lock.shield") {
            ContentView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
