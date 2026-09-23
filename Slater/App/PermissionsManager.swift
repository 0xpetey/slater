import AppKit
import CoreGraphics
import Observation

@MainActor
@Observable
final class PermissionsManager {
    private(set) var hasScreenRecording = CGPreflightScreenCaptureAccess()

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
