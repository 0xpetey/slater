import SwiftUI

@main
struct SlaterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar item is AppKit (StatusItemController), so the lizard can spin on hover.
        Settings {
            SettingsView(translator: appDelegate.appState.translator)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests use the app as their host; don't register hotkeys or show onboarding.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        statusItem = StatusItemController(appState: appState)
        appState.start()
    }
}
