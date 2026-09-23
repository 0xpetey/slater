import SwiftUI

@main
struct SlaterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Slater", systemImage: "lizard.fill") {
            MenuContent(appState: appDelegate.appState)
        }
        Settings {
            SettingsView(translator: appDelegate.appState.translator)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests use the app as their host; don't register hotkeys or show onboarding.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        appState.start()
    }
}
