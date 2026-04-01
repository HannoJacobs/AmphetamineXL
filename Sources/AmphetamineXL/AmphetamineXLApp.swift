import SwiftUI

@MainActor
final class AppLifecycleBridge {
    static let shared = AppLifecycleBridge()
    var appState: AppState?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppLifecycleBridge.shared.appState?.handleApplicationShouldTerminate(sender) ?? .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLifecycleBridge.shared.appState?.handleAppWillTerminate()
    }
}

@main
struct AmphetamineXLApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        let _ = AppLifecycleBridge.shared.appState = appState
        MenuBarExtra("AmphetamineXL", systemImage: appState.menuBarIcon) {
            MenuBarView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)
    }
}
