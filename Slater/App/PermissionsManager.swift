import AppKit
import CoreGraphics
import Observation

@MainActor
@Observable
final class PermissionsManager {
    /// False until `check()` or `refresh()` has asked.
    private(set) var hasScreenRecording = false

    /// Asks off the main thread. The answer takes about 10 ms to come back, which would
    /// otherwise hold up the menu bar item at launch.
    func check() async {
        hasScreenRecording = await Task.detached { CGPreflightScreenCaptureAccess() }.value
    }

    func refresh() {
        hasScreenRecording = CGPreflightScreenCaptureAccess()
    }

    /// Shows the system prompt the first time. After that, macOS only lists Slater
    /// in System Settings, so the user has to switch it on there.
    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// macOS often keeps reporting no access until the app restarts after the user grants it.
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
