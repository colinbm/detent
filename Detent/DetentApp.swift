import SwiftUI

@main struct DetentApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: model)
        } label: {
            Image(nsImage: .menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
