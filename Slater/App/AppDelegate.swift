import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var statusItem: StatusItemController?
    private var keyWindowObserver: NSObjectProtocol?

    func applicationWillFinishLaunching(_ notification: Notification) {
        LaunchTiming.log("App delegate reached")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests use the app as their host; don't register hotkeys or show onboarding.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        statusItem = StatusItemController(appState: appState)
        appState.start()
        LaunchTiming.log("Menu bar item and hotkeys up")
        LaunchTiming.logFirstIdle()
        installMainMenuOnceAWindowIsKey()
        // Once the menu bar item and hotkeys are up, and from the run loop rather than a task:
        // a modal alert inside a main-actor task stalls every other one until it's dismissed.
        RunLoop.main.perform {
            MainActor.assumeIsolated { ProblemReporter.offerCrashReportIfNeeded() }
        }
        #if DEBUG
        ProblemReporter.crashForTestingIfAsked()
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        ProblemReporter.sessionEnded()
    }

    /// The main menu's key equivalents matter once one of Slater's windows is key, so building
    /// it, about 5 ms, waits until then rather than holding up the menu bar item.
    func installMainMenuOnceAWindowIsKey() {
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.installMainMenu() }
        }
    }

    private func installMainMenu() {
        guard let keyWindowObserver else { return }
        NotificationCenter.default.removeObserver(keyWindowObserver)
        self.keyWindowObserver = nil
        NSApp.mainMenu = MainMenu.make(settingsAction: #selector(openSettings), helpAction: #selector(openHelp), target: self)
    }

    @objc private func openSettings(_ sender: Any?) {
        appState.showSettings()
    }

    @objc private func openHelp(_ sender: Any?) {
        appState.showHelp()
    }
}
