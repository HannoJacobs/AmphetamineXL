import SwiftUI

@main
struct AmphetamineXLApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("AmphetamineXL", systemImage: appState.menuBarIcon) {
            MenuBarView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)
    }
}
